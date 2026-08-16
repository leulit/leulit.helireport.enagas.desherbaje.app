import 'dart:async';

import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';
import 'package:sqflite/sqflite.dart';

import '../contracts/auth_expired_exception.dart';
import '../contracts/syncable.dart';
import '../outbox/outbox_queue.dart';
import '../sync_actions.dart';
import '../type_registry.dart';
import 'cancel_token.dart';
import 'pull_context.dart';
import 'pull_outcome.dart';
import 'pull_progress.dart';
import 'tasks/apply_resolver_task.dart';
import 'tasks/detect_conflicts_task.dart';
import 'tasks/dispatch_pull_completed_task.dart';
import 'tasks/enqueue_conflicts_task.dart';
import 'tasks/invoke_remote_fetcher_task.dart';
import 'tasks/update_pull_state_task.dart';
import 'tasks/upsert_non_conflicting_task.dart';

class PullSummary {
  final int total;
  final int upserted;
  final int conflicts;
  final bool cancelled;
  final bool authExpired;
  final PullOutcome outcome;
  final String? errorMessage;

  /// A degraded summary means the pull ended with a non-clean outcome
  /// (blocking error or partial item failures).
  bool get isDegraded =>
      outcome == PullOutcome.error || outcome == PullOutcome.partial;

  const PullSummary({
    required this.total,
    required this.upserted,
    required this.conflicts,
    required this.cancelled,
    required this.outcome,
    this.authExpired = false,
    this.errorMessage,
  });
}

/// Coordinates a manual pull for a single entity type. Built around a
/// [TaskPipeline] so each phase is isolated and unit-testable.
///
/// Cancellation is cooperative: callers pass a [CancelToken]; tasks check
/// it between iterations. Items already upserted before cancellation
/// remain persisted — there is no rollback.
///
/// Error policy:
/// - Blocking pipeline failure (AuthExpiredException): dispatches authExpired,
///   writes `auth_expired` to pull_state, does NOT fire cloudPullCompleted.
/// - Blocking pipeline failure (other): sets ctx.blockingError, writes `error`
///   to pull_state, does NOT fire cloudPullCompleted.
/// - Non-blocking per-item failures: accumulated in ctx.partialErrors; outcome
///   becomes `partial`; cloudPullCompleted IS fired with outcome=partial.
class PullCoordinator<T extends Syncable> {
  final TypeRegistration<T> _registration;
  final OutboxQueue _outbox;
  final Database _db;

  PullCoordinator({
    required this._registration,
    required this._outbox,
    required this._db,
  });

  Future<PullSummary> pullNow({
    CancelToken? token,
    void Function(PullProgress)? onProgress,
  }) async {
    final ctx = PullContext<T>(registration: _registration, cancelToken: token);

    final tasks = <PipelineTask<PullContext<T>>>[
      InvokeRemoteFetcherTask<T>(),
      DetectConflictsTask<T>(outbox: _outbox),
      ApplyResolverTask<T>(),
      UpsertNonConflictingTask<T>(),
      EnqueueConflictsTask<T>(db: _db),
      UpdatePullStateTask<T>(db: _db),
      DispatchPullCompletedTask<T>(),
    ];
    final total = tasks.length;

    // broadcast: true so we can subscribe + the pipeline can also emit without
    // "Stream already listened to" errors (belt-and-suspenders for [REVIEW G2]).
    final pipeline = TaskPipeline<PullContext<T>>(broadcast: true);
    for (final task in tasks) {
      pipeline.addTask(task);
    }

    // Surface pipeline step transitions as UI progress. The first step (the
    // remote fetch) is of unknown duration → emit a null fraction so the bar
    // animates as indeterminate; subsequent (fast) steps fill it determinately.
    StreamSubscription<PipelineEvent<PullContext<T>>>? progressSub;
    if (onProgress != null) {
      var completed = 0;
      progressSub = pipeline.events.listen((event) {
        switch (event.type) {
          case PipelineEventType.taskStart:
            onProgress(PullProgress(
              fraction: completed == 0 ? null : completed / total,
              phase: _phaseLabel(event.stepName),
            ));
          case PipelineEventType.taskSuccess:
            completed++;
            onProgress(PullProgress(
              fraction: completed / total,
              phase: _phaseLabel(event.stepName),
            ));
          case PipelineEventType.pipelineStart:
          case PipelineEventType.pipelineEnd:
          case PipelineEventType.error:
            break;
        }
      });
    }

    try {
      final result = await pipeline.run(DataPipeline.of(ctx));

      if (result.isFailure) {
        final error = result.errorOrNull!;
        if (error is AuthExpiredException) {
          ctx.authExpired = true;
          SyncActions.authExpired.dispatch();
          await _writePullStateBlocking(ctx.registration.entityType, ctx);
        } else {
          // NF-1: non-auth blocking failure — no longer silent.
          ctx.blockingError = error;
          await _writePullStateBlocking(ctx.registration.entityType, ctx);
        }
        // Blocking failure: do NOT dispatch cloudPullCompleted (NF-6).
        return _summary(ctx);
      }

      // Pipeline succeeded (including partial). UpdatePullStateTask and
      // DispatchPullCompletedTask already ran inside the pipeline.
      return _summary(ctx);
    } on AuthExpiredException {
      ctx.authExpired = true;
      SyncActions.authExpired.dispatch();
      await _writePullStateBlocking(ctx.registration.entityType, ctx);
      return _summary(ctx);
    } finally {
      await progressSub?.cancel();
      pipeline.dispose();
    }
  }

  static String _phaseLabel(String stepName) {
    switch (stepName) {
      case 'InvokeRemoteFetcher':
        return 'Descargando…';
      case 'DetectConflicts':
        return 'Comprobando cambios…';
      case 'ApplyResolver':
        return 'Resolviendo cambios…';
      case 'UpsertNonConflicting':
        return 'Guardando…';
      case 'EnqueueConflicts':
        return 'Resolviendo conflictos…';
      case 'UpdatePullState':
        return 'Actualizando estado…';
      case 'DispatchPullCompleted':
        return 'Finalizando…';
      default:
        return 'Descargando…';
    }
  }

  PullSummary _summary(PullContext<T> ctx) => PullSummary(
        total: ctx.remoteItems.length,
        upserted: ctx.upserted,
        conflicts: ctx.conflicts.length,
        cancelled: ctx.cancelled,
        authExpired: ctx.authExpired,
        outcome: ctx.outcome,
        errorMessage: ctx.errorMessage,
      );

  Future<void> _writePullStateBlocking(
    String entityType,
    PullContext<T> ctx,
  ) async {
    try {
      await UpdatePullStateTask.writePullState(
        _db,
        entityType,
        ctx.outcome,
        ctx.errorMessage,
      );
    } catch (_) {
      // Best-effort: if we can't write pull_state during error handling,
      // don't mask the original error.
    }
  }
}
