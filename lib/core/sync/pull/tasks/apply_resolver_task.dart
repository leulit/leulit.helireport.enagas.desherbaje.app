import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

import '../../contracts/syncable.dart';
import '../pull_context.dart';

/// Invokes `registration.conflictResolver` for every item [DetectConflictsTask]
/// classified as a conflict, closing the gap between the resolver contract
/// (`ConflictResolver.resolve` — see its doc-comment) and the pipeline: before
/// this task existed, the resolver configured per entity was never called and
/// every conflict landed in `sync_conflicts` regardless of the resolver.
///
/// - Resolver returns non-null → the divergence is decided. Reclassify the
///   item out of `ctx.conflicts` and into `ctx.safeToUpsert` under the
///   resolved entity, so [UpsertNonConflictingTask] persists it like any
///   other non-conflicting item and [EnqueueConflictsTask] never sees it.
/// - Resolver returns null (only [InteractiveConflictResolver]) → defer to
///   the user. The item stays in `ctx.conflicts` unchanged — same behavior
///   as before this task existed.
class ApplyResolverTask<T extends Syncable>
    extends PipelineTask<PullContext<T>> {
  @override
  String get name => 'ApplyResolver';

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

    // Snapshot before iterating: the loop body mutates ctx.conflicts.
    final pending = List<ResolvedPullItem<T>>.from(ctx.conflicts);
    for (final item in pending) {
      if (ctx.isCancelRequested) {
        ctx.cancelled = true;
        return DataPipeline.success(input: ctx, output: ctx);
      }

      // local is guaranteed non-null for conflict items (DetectConflictsTask
      // only adds items here when a local row was found).
      final local = item.local;
      if (local == null) continue;

      final resolved = ctx.registration.conflictResolver.resolve(
        local: local,
        remote: item.remote,
      );
      if (resolved == null) continue; // deferred to the user — unchanged.

      ctx.conflicts.removeWhere((c) => c.clientId == item.clientId);
      ctx.safeToUpsert.add(
        (remote: resolved, clientId: item.clientId, local: item.local),
      );
    }
    return DataPipeline.success(input: ctx, output: ctx);
  }
}
