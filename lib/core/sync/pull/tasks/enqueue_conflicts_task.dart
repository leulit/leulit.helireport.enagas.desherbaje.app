import 'dart:convert';

import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';
import 'package:sqflite/sqflite.dart';

import '../../contracts/syncable.dart';
import '../../database/offline_database.dart';
import '../../sync_actions.dart';
import '../pull_context.dart';

/// Inserts every divergent remote item into `sync_conflicts` so the
/// operator can resolve it from the sync page. Dispatches one
/// `entityConflict` action per row.
class EnqueueConflictsTask<T extends Syncable>
    extends PipelineTask<PullContext<T>> {
  final Database db;

  EnqueueConflictsTask({required this.db});

  @override
  String get name => 'EnqueueConflicts';

  @override
  bool get isBlocking => false;

  @override
  Future<DataPipeline<PullContext<T>>> execute(
    DataPipeline<PullContext<T>> data,
  ) async {
    final ctx = data.output;
    if (ctx.cancelled) return DataPipeline.success(input: ctx, output: ctx);

    for (final remote in ctx.conflicts) {
      if (ctx.isCancelRequested) {
        ctx.cancelled = true;
        return DataPipeline.success(input: ctx, output: ctx);
      }
      final local = await ctx.registration.store.findByClientId(remote.clientId);
      if (local == null) continue;

      await db.insert(
        OfflineDatabase.syncConflictsTable,
        {
          'entity_type': ctx.registration.entityType,
          'client_id': remote.clientId,
          'local_json': jsonEncode(local.toJson()),
          'remote_json': jsonEncode(remote.toJson()),
          'detected_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      SyncActions.entityConflict.dispatch(
        data: EntityConflictEvent(
          entityType: ctx.registration.entityType,
          clientId: remote.clientId,
        ),
      );
    }
    return DataPipeline.success(input: ctx, output: ctx);
  }
}
