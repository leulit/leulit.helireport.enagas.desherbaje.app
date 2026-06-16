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
///
/// Consumes [ResolvedPullItem] so the local copy is already in hand —
/// no extra DB lookup per item (avoids the previous N+1).
///
/// Per-item failures are non-fatal: on DB error the item is skipped and a
/// [PullTaskError] is added to [PullContext.partialErrors], but the remaining
/// conflicts continue to be enqueued.
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

    for (final item in ctx.conflicts) {
      if (ctx.isCancelRequested) {
        ctx.cancelled = true;
        return DataPipeline.success(input: ctx, output: ctx);
      }

      // local is guaranteed non-null for conflict items (DetectConflictsTask
      // only adds items here when a local row was found).
      final local = item.local;
      if (local == null) continue;

      try {
        await db.insert(
          OfflineDatabase.syncConflictsTable,
          {
            'entity_type': ctx.registration.entityType,
            'client_id': item.clientId,
            'local_json': jsonEncode(local.toJson()),
            'remote_json': jsonEncode(item.remote.toJson()),
            'detected_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        SyncActions.entityConflict.dispatch(
          data: EntityConflictEvent(
            entityType: ctx.registration.entityType,
            clientId: item.clientId,
          ),
        );
      } catch (e) {
        ctx.partialErrors.add(PullTaskError(name, e));
        continue;
      }
    }
    return DataPipeline.success(input: ctx, output: ctx);
  }
}
