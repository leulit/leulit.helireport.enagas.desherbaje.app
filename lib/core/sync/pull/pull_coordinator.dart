import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';
import 'package:sqflite/sqflite.dart';

import '../contracts/auth_expired_exception.dart';
import '../contracts/syncable.dart';
import '../outbox/outbox_queue.dart';
import '../sync_actions.dart';
import '../type_registry.dart';
import 'cancel_token.dart';
import 'pull_context.dart';
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

  const PullSummary({
    required this.total,
    required this.upserted,
    required this.conflicts,
    required this.cancelled,
    this.authExpired = false,
  });
}

/// Coordinates a manual pull for a single entity type. Built around a
/// [TaskPipeline] so each phase is isolated and unit-testable.
///
/// Cancellation is cooperative: callers pass a [CancelToken]; tasks check
/// it between iterations. Items already upserted before cancellation
/// remain persisted — there is no rollback.
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
    final pipeline = TaskPipeline<PullContext<T>>()
      ..addTask(InvokeRemoteFetcherTask<T>())
      ..addTask(DetectConflictsTask<T>(outbox: _outbox))
      ..addTask(UpsertNonConflictingTask<T>())
      ..addTask(EnqueueConflictsTask<T>(db: _db))
      ..addTask(UpdatePullStateTask<T>(db: _db))
      ..addTask(DispatchPullCompletedTask<T>());

    try {
      final result = await pipeline.run(DataPipeline.of(ctx));
      pipeline.dispose();
      if (result.isFailure && result.errorOrNull is AuthExpiredException) {
        SyncActions.authExpired.dispatch();
        return PullSummary(
          total: ctx.remoteItems.length,
          upserted: ctx.upserted,
          conflicts: ctx.conflicts.length,
          cancelled: ctx.cancelled,
          authExpired: true,
        );
      }
    } on AuthExpiredException {
      pipeline.dispose();
      SyncActions.authExpired.dispatch();
      return PullSummary(
        total: ctx.remoteItems.length,
        upserted: ctx.upserted,
        conflicts: ctx.conflicts.length,
        cancelled: ctx.cancelled,
        authExpired: true,
      );
    }
    return PullSummary(
      total: ctx.remoteItems.length,
      upserted: ctx.upserted,
      conflicts: ctx.conflicts.length,
      cancelled: ctx.cancelled,
    );
  }
}
