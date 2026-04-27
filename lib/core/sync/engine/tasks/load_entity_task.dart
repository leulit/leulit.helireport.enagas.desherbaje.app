import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

import '../../contracts/sync_job.dart';
import '../sync_job_context.dart';

/// Loads the entity from its [LocalStore] using the job's `clientId`.
///
/// Blocking: a missing entity for a non-delete operation is a programming
/// error (the repository should have persisted before enqueueing) and there
/// is nothing the rest of the pipeline can do.
class LoadEntityTask extends PipelineTask<SyncJobContext> {
  @override
  String get name => 'LoadEntity';

  @override
  bool get isBlocking => true;

  @override
  Future<DataPipeline<SyncJobContext>> execute(
    DataPipeline<SyncJobContext> data,
  ) async {
    final ctx = data.output;
    final entity = await ctx.registration.store.findByClientId(ctx.job.clientId);
    if (entity == null && ctx.job.operation != SyncOperation.delete) {
      return DataPipeline.error(
        input: ctx,
        error: StateError(
          'Entity ${ctx.job.entityType}/${ctx.job.clientId} not found locally '
          'for job ${ctx.job.id} (${ctx.job.operation.name}).',
        ),
      );
    }
    ctx.entity = entity;
    return DataPipeline.success(input: ctx, output: ctx);
  }
}
