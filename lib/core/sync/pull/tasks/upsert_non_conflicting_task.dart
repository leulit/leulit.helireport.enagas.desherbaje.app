import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

import '../../contracts/sync_job.dart';
import '../../contracts/syncable.dart';
import '../../sync_actions.dart';
import '../pull_context.dart';

/// Persists every non-conflicting remote item into the local store and
/// dispatches an `entitySynced` action per item so listening UIs refresh.
class UpsertNonConflictingTask<T extends Syncable>
    extends PipelineTask<PullContext<T>> {
  @override
  String get name => 'UpsertNonConflicting';

  @override
  bool get isBlocking => false;

  @override
  Future<DataPipeline<PullContext<T>>> execute(
    DataPipeline<PullContext<T>> data,
  ) async {
    final ctx = data.output;
    if (ctx.cancelled) return DataPipeline.success(input: ctx, output: ctx);

    for (final remote in ctx.safeToUpsert) {
      if (ctx.isCancelRequested) {
        ctx.cancelled = true;
        return DataPipeline.success(input: ctx, output: ctx);
      }
      await ctx.registration.store.upsert(remote);
      await ctx.registration.store.markSynced(
        clientId: remote.clientId,
        remoteId: remote.remoteId,
      );
      ctx.upserted++;
      SyncActions.entitySynced.dispatch(
        data: EntitySyncedEvent(
          entityType: ctx.registration.entityType,
          clientId: remote.clientId,
          operation: SyncOperation.update,
          remoteId: remote.remoteId,
        ),
      );
    }
    return DataPipeline.success(input: ctx, output: ctx);
  }
}
