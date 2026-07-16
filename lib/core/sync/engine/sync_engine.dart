import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';
import 'package:sqflite/sqflite.dart';

import '../contracts/auth_expired_exception.dart';
import '../outbox/outbox_queue.dart';
import '../sync_actions.dart';
import '../type_registry.dart';
import 'sync_job_context.dart';
import 'tasks/dispatch_action_task.dart';
import 'tasks/interpret_outcome_task.dart';
import 'tasks/invoke_remote_adapter_task.dart';
import 'tasks/load_entity_task.dart';
import 'tasks/update_local_state_task.dart';

/// Aggregated outcome of a [SyncEngine.drain] call. Surfaced to the UI so
/// the operator sees a per-category summary.
class DrainSummary {
  final int succeeded;
  final int retryable;
  final int rejected;
  final int conflicts;
  final bool authExpired;

  const DrainSummary({
    this.succeeded = 0,
    this.retryable = 0,
    this.rejected = 0,
    this.conflicts = 0,
    this.authExpired = false,
  });

  DrainSummary copyWith({
    int? succeeded,
    int? retryable,
    int? rejected,
    int? conflicts,
    bool? authExpired,
  }) =>
      DrainSummary(
        succeeded: succeeded ?? this.succeeded,
        retryable: retryable ?? this.retryable,
        rejected: rejected ?? this.rejected,
        conflicts: conflicts ?? this.conflicts,
        authExpired: authExpired ?? this.authExpired,
      );

  int get total => succeeded + retryable + rejected + conflicts;
}

/// Drains the outbox on demand. No timers, no connectivity listeners, no
/// retry policy — only what the UI explicitly asks for.
///
/// The drain is "continue on error": failures of one job do not abort the
/// drain. Only [AuthExpiredException] aborts immediately and dispatches
/// [SyncActions.authExpired].
class SyncEngine {
  final OutboxQueue _outbox;
  final TypeRegistry _registry;
  final Database _db;

  bool _isDraining = false;

  SyncEngine({
    required OutboxQueue outbox,
    required TypeRegistry registry,
    required Database db,
  })  : _outbox = outbox,
        _registry = registry,
        _db = db;

  bool get isDraining => _isDraining;

  /// Drains pending jobs (optionally filtered to a single [entityType]).
  /// Returns a [DrainSummary] with counts. Concurrent calls are coalesced:
  /// a second call while one drain is already running returns an empty
  /// summary immediately to avoid double processing.
  ///
  /// Termination is guaranteed by a [Set<int>] of already-processed job ids:
  /// even if [OutboxQueue.markPendingAgain] puts a retryable job back to
  /// `pending`, it will not be re-fetched within the same drain call.
  Future<DrainSummary> drain({
    String? entityType,
    Set<String>? onlyClientIds,
  }) async {
    if (_isDraining) return const DrainSummary();
    _isDraining = true;

    // Hoist the pipeline: the 5 tasks are stateless; build once, reuse per job.
    final pipeline = TaskPipeline<SyncJobContext>()
      ..addTask(LoadEntityTask())
      ..addTask(InvokeRemoteAdapterTask())
      ..addTask(InterpretOutcomeTask())
      ..addTask(UpdateLocalStateTask(outbox: _outbox, db: _db))
      ..addTask(DispatchActionTask());

    var summary = const DrainSummary();
    final processed = <int>{};

    try {
      while (true) {
        final batch = await _outbox.nextPending(
          entityType: entityType,
          limit: 100,
          onlyClientIds: onlyClientIds,
        );

        // Filter out ids already processed in this drain to prevent infinite
        // loops when retryable jobs are put back to `pending`.
        final fresh = batch.where((j) => !processed.contains(j.id)).toList();
        if (fresh.isEmpty) break;

        for (final job in fresh) {
          processed.add(job.id);

          final registration = _registry.lookup(job.entityType);
          if (registration == null) {
            await _outbox.markRejected(
              job.id,
              error: 'No registration for type "${job.entityType}"',
            );
            summary = summary.copyWith(rejected: summary.rejected + 1);
            continue;
          }
          if (!registration.hasAdapter) {
            await _outbox.markRejected(
              job.id,
              error: 'Type "${job.entityType}" is read-only (no adapter)',
            );
            summary = summary.copyWith(rejected: summary.rejected + 1);
            continue;
          }

          await _outbox.markSyncing(job.id);
          final ctx = SyncJobContext(job: job, registration: registration);

          final result = await pipeline.run(DataPipeline.of(ctx));

          if (result.isFailure && result.errorOrNull is AuthExpiredException) {
            // Roll back the syncing flag so the job retries cleanly after
            // re-login. The reclaim-on-startup path also handles this if
            // the app is killed before we get here.
            await _outbox.markPendingAgain(
              job.id,
              error: 'Auth expired, drain aborted',
            );
            summary = summary.copyWith(authExpired: true);
            SyncActions.authExpired.dispatch();
            return summary;
          }

          if (result.isFailure) {
            // Pipeline failed in a blocking task other than auth.
            // Treat as retryable so the user can try again.
            await _outbox.markPendingAgain(
              job.id,
              error: result.errorOrNull?.toString() ?? 'Unknown pipeline error',
            );
            summary = summary.copyWith(retryable: summary.retryable + 1);
            continue;
          }

          summary = switch (ctx.result!) {
            SyncJobResult.succeeded =>
              summary.copyWith(succeeded: summary.succeeded + 1),
            SyncJobResult.retryable =>
              summary.copyWith(retryable: summary.retryable + 1),
            SyncJobResult.rejected =>
              summary.copyWith(rejected: summary.rejected + 1),
            SyncJobResult.conflict =>
              summary.copyWith(conflicts: summary.conflicts + 1),
          };
        }
      }
    } finally {
      pipeline.dispose();
      _isDraining = false;
    }
    return summary;
  }
}
