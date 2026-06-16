import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

import '../../contracts/sync_job.dart';
import '../../contracts/syncable.dart';
import '../../outbox/outbox_queue.dart';
import '../pull_context.dart';

/// Splits the items returned by the remote fetcher into:
/// - `safeToUpsert`: those without local divergence.
/// - `conflicts`: those whose local copy is more recent than remote OR
///   whose `client_id` has a pending/syncing outbox job (operator's offline
///   edits not yet pushed or currently being pushed).
///
/// **Identity resolution (BE-1 bridge):** when the backend omits `client_id`,
/// `fromJson` mints a new UUID for every pull. This task first tries to match
/// the remote item's `remoteId` against the local store. When a match is found,
/// the *local* `clientId` becomes the canonical identity — preventing the
/// `ConflictAlgorithm.replace` from silently destroying an edited local row.
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

      // Step 1 — resolve the canonical local identity.
      // First try matching by remoteId (covers the case where the backend
      // omits client_id and fromJson mints a fresh UUID each pull).
      T? local;
      String resolvedClientId = remote.clientId;

      if (remote.remoteId != null) {
        final byRemote =
            await ctx.registration.store.findByRemoteId(remote.remoteId!);
        if (byRemote != null) {
          // Use the local row's clientId as the canonical identity.
          local = byRemote;
          resolvedClientId = byRemote.clientId;
        }
      }

      // Fall back to clientId lookup if remoteId gave no match.
      if (local == null) {
        local = await ctx.registration.store.findByClientId(remote.clientId);
        // resolvedClientId stays remote.clientId (new entity or clientId echo).
      }

      // Step 2 — classify.
      if (local == null) {
        // Completely new item — safe to upsert under whatever clientId we have.
        ctx.safeToUpsert.add(
          (remote: remote, clientId: resolvedClientId, local: null),
        );
        continue;
      }

      final hasPending = pendingClientIds.contains(local.clientId);
      final localIsNewer = local.updatedAt.isAfter(remote.updatedAt);

      if (localIsNewer || hasPending) {
        ctx.conflicts.add(
          (remote: remote, clientId: resolvedClientId, local: local),
        );
      } else {
        ctx.safeToUpsert.add(
          (remote: remote, clientId: resolvedClientId, local: local),
        );
      }
    }
    return DataPipeline.success(input: ctx, output: ctx);
  }

  Future<Set<String>> _pendingClientIds(String entityType) async {
    final pending = await outbox.pendingJobs(entityType: entityType);
    final rejected = await outbox.rejectedJobs(entityType: entityType);
    final syncing = await outbox.syncingJobs(entityType: entityType);
    return {
      for (final job in pending)
        if (job.operation != SyncOperation.delete) job.clientId,
      for (final job in rejected)
        if (job.operation != SyncOperation.delete) job.clientId,
      for (final job in syncing)
        if (job.operation != SyncOperation.delete) job.clientId,
    };
  }
}
