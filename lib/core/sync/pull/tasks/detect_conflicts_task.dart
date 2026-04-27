import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

import '../../contracts/sync_job.dart';
import '../../contracts/syncable.dart';
import '../../outbox/outbox_queue.dart';
import '../pull_context.dart';

/// Splits the items returned by the remote fetcher into:
/// - `safeToUpsert`: those without local divergence.
/// - `conflicts`: those whose local copy is more recent than remote OR
///   whose `client_id` has a pending outbox job (operator's offline edits
///   not yet pushed).
class DetectConflictsTask<T extends Syncable>
    extends PipelineTask<PullContext<T>> {
  final OutboxQueue outbox;

  DetectConflictsTask({required this.outbox});

  @override
  String get name => 'DetectConflicts';

  @override
  bool get isBlocking => true;

  @override
  Future<DataPipeline<PullContext<T>>> execute(
    DataPipeline<PullContext<T>> data,
  ) async {
    final ctx = data.output;
    if (ctx.cancelled) return DataPipeline.success(input: ctx, output: ctx);
    if (ctx.isCancelRequested) {
      ctx.cancelled = true;
      return DataPipeline.success(input: ctx, output: ctx);
    }

    final pendingClientIds =
        await _pendingClientIds(ctx.registration.entityType);

    for (final remote in ctx.remoteItems) {
      if (ctx.isCancelRequested) {
        ctx.cancelled = true;
        return DataPipeline.success(input: ctx, output: ctx);
      }
      final hasPendingOutbox = pendingClientIds.contains(remote.clientId);
      final local = await ctx.registration.store.findByClientId(remote.clientId);

      if (local == null) {
        ctx.safeToUpsert.add(remote);
        continue;
      }
      final localIsNewer = local.updatedAt.isAfter(remote.updatedAt);
      if (localIsNewer || hasPendingOutbox) {
        ctx.conflicts.add(remote);
      } else {
        ctx.safeToUpsert.add(remote);
      }
    }
    return DataPipeline.success(input: ctx, output: ctx);
  }

  Future<Set<String>> _pendingClientIds(String entityType) async {
    final pending = await outbox.pendingJobs(entityType: entityType);
    final rejected = await outbox.rejectedJobs(entityType: entityType);
    return {
      for (final job in pending)
        if (job.operation != SyncOperation.delete) job.clientId,
      for (final job in rejected)
        if (job.operation != SyncOperation.delete) job.clientId,
    };
  }
}
