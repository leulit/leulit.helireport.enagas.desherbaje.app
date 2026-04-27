import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';
import 'package:sqflite/sqflite.dart';

import '../../contracts/syncable.dart';
import '../../database/offline_database.dart';
import '../pull_context.dart';

/// Records the outcome of the pull in `pull_state` so the sync page can
/// show "última descarga: hace X minutos" per entity.
class UpdatePullStateTask<T extends Syncable>
    extends PipelineTask<PullContext<T>> {
  final Database db;

  UpdatePullStateTask({required this.db});

  @override
  String get name => 'UpdatePullState';

  @override
  bool get isBlocking => false;

  @override
  Future<DataPipeline<PullContext<T>>> execute(
    DataPipeline<PullContext<T>> data,
  ) async {
    final ctx = data.output;
    final status = ctx.cancelled
        ? 'cancelled'
        : ctx.conflicts.isEmpty
            ? 'ok'
            : 'ok_with_conflicts';
    await db.insert(
      OfflineDatabase.pullStateTable,
      {
        'entity_type': ctx.registration.entityType,
        'last_pulled_at': DateTime.now().millisecondsSinceEpoch,
        'last_status': status,
        'last_error': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return DataPipeline.success(input: ctx, output: ctx);
  }
}
