import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

import '../../contracts/syncable.dart';
import '../../sync_actions.dart';
import '../pull_context.dart';

class DispatchPullCompletedTask<T extends Syncable>
    extends PipelineTask<PullContext<T>> {
  @override
  String get name => 'DispatchPullCompleted';

  @override
  bool get isBlocking => false;

  @override
  Future<DataPipeline<PullContext<T>>> execute(
    DataPipeline<PullContext<T>> data,
  ) async {
    final ctx = data.output;
    SyncActions.cloudPullCompleted.dispatch(
      data: CloudPullCompletedEvent(
        entityType: ctx.registration.entityType,
        upserted: ctx.upserted,
        conflicts: ctx.conflicts.length,
        cancelled: ctx.cancelled,
        outcome: ctx.outcome,
        errorMessage: ctx.errorMessage,
      ),
    );
    return DataPipeline.success(input: ctx, output: ctx);
  }
}
