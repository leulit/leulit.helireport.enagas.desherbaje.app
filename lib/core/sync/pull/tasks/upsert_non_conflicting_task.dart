import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

import '../../contracts/sync_job.dart';
import '../../contracts/syncable.dart';
import '../../sync_actions.dart';
import '../pull_context.dart';

/// Persists every non-conflicting remote item into the local store and
/// dispatches an `entitySynced` action per item so listening UIs refresh.
///
/// Uses the **resolved** [clientId] from each [ResolvedPullItem] — not the
/// raw UUID in the remote payload — to avoid accidentally creating a second row
/// when the backend omits `client_id` and `fromJson` minted a fresh UUID.
///
/// Per-item failures are non-fatal: on store error the item is skipped and a
/// [PullTaskError] is added to [PullContext.partialErrors], but the remaining
/// items continue to be persisted.
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

    for (final item in ctx.safeToUpsert) {
      if (ctx.isCancelRequested) {
        ctx.cancelled = true;
        return DataPipeline.success(input: ctx, output: ctx);
      }

      try {
        // Re-bind the remote entity under the canonical local clientId so
        // the store's update-then-insert reconciliation matches the right row.
        final rebound = ctx.registration.fromJson(
          {...item.remote.toJson(), 'client_id': item.clientId},
        );

        await ctx.registration.store.upsert(rebound);
        await ctx.registration.store.markSynced(
          clientId: item.clientId,
          remoteId: item.remote.remoteId,
        );
        ctx.upserted++;
        SyncActions.entitySynced.dispatch(
          data: EntitySyncedEvent(
            entityType: ctx.registration.entityType,
            clientId: item.clientId,
            operation: SyncOperation.update,
            remoteId: item.remote.remoteId,
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
