import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';
import 'package:sqflite/sqflite.dart';

import '../../contracts/syncable.dart';
import '../../database/offline_database.dart';
import '../pull_context.dart';
import '../pull_outcome.dart';

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
    await writePullState(
      db,
      ctx.registration.entityType,
      ctx.outcome,
      ctx.errorMessage,
    );
    return DataPipeline.success(input: ctx, output: ctx);
  }

  /// Writes [outcome] and [errorMessage] to `pull_state` for [entityType].
  ///
  /// Extracted as a static so [PullCoordinator] can reuse it when handling
  /// blocking pipeline failures (before tasks run) without duplicating the
  /// SQL logic.
  static Future<void> writePullState(
    Database db,
    String entityType,
    PullOutcome outcome,
    String? errorMessage,
  ) async {
    await db.insert(
      OfflineDatabase.pullStateTable,
      {
        'entity_type': entityType,
        'last_pulled_at': DateTime.now().millisecondsSinceEpoch,
        'last_status': outcome.statusString,
        'last_error': errorMessage,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
