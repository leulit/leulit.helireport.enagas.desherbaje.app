import 'dart:convert';

import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';
import 'package:sqflite/sqflite.dart';

import '../../contracts/remote_adapter.dart';
import '../../contracts/sync_job.dart';
import '../../database/offline_database.dart';
import '../../outbox/outbox_queue.dart';
import '../sync_job_context.dart';

/// Persists the side effects of the outcome:
/// - Success → outbox markSynced + (depending on operation) update local
///   row with serverVersion / mark synced / delete row.
/// - Retryable → outbox markPendingAgain.
/// - Rejected → outbox markRejected with the legible error.
/// - Conflict → outbox markRejected ("conflict") and a row is inserted in
///   `sync_conflicts` so the user can resolve it from the sync page.
class UpdateLocalStateTask extends PipelineTask<SyncJobContext> {
  final OutboxQueue outbox;
  final Database db;

  UpdateLocalStateTask({required this.outbox, required this.db});

  @override
  String get name => 'UpdateLocalState';

  @override
  bool get isBlocking => false;

  @override
  Future<DataPipeline<SyncJobContext>> execute(
    DataPipeline<SyncJobContext> data,
  ) async {
    final ctx = data.output;
    final outcome = ctx.outcome!;
    final job = ctx.job;
    final store = ctx.registration.store;

    switch (outcome) {
      case SyncSuccess(:final remoteId, :final serverVersion):
        await outbox.markSynced(job.id, remoteId: remoteId);
        if (job.operation == SyncOperation.delete) {
          await store.delete(job.clientId);
        } else {
          if (serverVersion != null) {
            await store.upsert(serverVersion);
          }
          await store.markSynced(clientId: job.clientId, remoteId: remoteId);
        }

      case SyncRetryable(:final reason):
        await outbox.markPendingAgain(job.id, error: reason);

      case SyncUnrecoverable(:final reason, :final statusCode, :final errorMessageEs):
        await outbox.markRejected(
          job.id,
          error: errorMessageEs ?? reason,
          statusCode: statusCode,
        );

      case SyncConflict(:final serverVersion):
        await outbox.markRejected(job.id, error: 'Conflict (409)');
        final local = ctx.entity;
        if (local != null) {
          await db.insert(
            OfflineDatabase.syncConflictsTable,
            {
              'entity_type': job.entityType,
              'client_id': job.clientId,
              'local_json': jsonEncode(local.toJson()),
              'remote_json': jsonEncode(serverVersion.toJson()),
              'detected_at': DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
    }
    return DataPipeline.success(input: ctx, output: ctx);
  }
}
