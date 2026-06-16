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
    required TypeRegistration<T> registration,
    required OutboxQueue outbox,
    required Database db,
  })  : _registration = registration,
        _outbox = outbox,
        _db = db;

  Future<PullSummary> pullNow({CancelToken? token}) async {
    final ctx = PullContext<T>(registration: _registration, cancelToken: token);

    // broadcast: true so we can subscribe + the pipeline can also emit without
    // "Stream already listened to" errors (belt-and-suspenders for [REVIEW G2]).
    final pipeline = TaskPipeline<PullContext<T>>(broadcast: true)
      ..addTask(InvokeRemoteFetcherTask<T>())
      ..addTask(DetectConflictsTask<T>(outbox: _outbox))
      ..addTask(UpsertNonConflictingTask<T>())
      ..addTask(EnqueueConflictsTask<T>(db: _db))
      ..addTask(UpdatePullStateTask<T>(db: _db))
      ..addTask(DispatchPullCompletedTask<T>());

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
      pipeline.dispose();
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
