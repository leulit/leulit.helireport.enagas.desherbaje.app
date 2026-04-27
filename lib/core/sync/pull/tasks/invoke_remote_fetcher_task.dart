import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

import '../../contracts/syncable.dart';
import '../pull_context.dart';

class InvokeRemoteFetcherTask<T extends Syncable>
    extends PipelineTask<PullContext<T>> {
  @override
  String get name => 'InvokeRemoteFetcher';

  @override
  bool get isBlocking => true;

  @override
  Future<DataPipeline<PullContext<T>>> execute(
    DataPipeline<PullContext<T>> data,
  ) async {
    final ctx = data.output;
    final fetcher = ctx.registration.fetcher;
    if (fetcher == null) {
      return DataPipeline.error(
        input: ctx,
        error: StateError(
          'Type ${ctx.registration.entityType} has no RemoteFetcher.',
        ),
      );
    }
    if (ctx.isCancelRequested) {
      ctx.cancelled = true;
      return DataPipeline.success(input: ctx, output: ctx);
    }
    ctx.remoteItems = await fetcher.pullAll();
    return DataPipeline.success(input: ctx, output: ctx);
  }
}
