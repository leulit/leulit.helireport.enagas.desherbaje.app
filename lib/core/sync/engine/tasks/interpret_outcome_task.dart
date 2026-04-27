import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

import '../../contracts/remote_adapter.dart';
import '../sync_job_context.dart';

/// Inspects [SyncJobContext.outcome] and classifies it into a
/// [SyncJobResult] that the next tasks can act on without re-pattern-matching.
class InterpretOutcomeTask extends PipelineTask<SyncJobContext> {
  @override
  String get name => 'InterpretOutcome';

  @override
  bool get isBlocking => true;

  @override
  Future<DataPipeline<SyncJobContext>> execute(
    DataPipeline<SyncJobContext> data,
  ) async {
    final ctx = data.output;
    final outcome = ctx.outcome;
    if (outcome == null) {
      return DataPipeline.error(
        input: ctx,
        error: StateError('Outcome missing before InterpretOutcome'),
      );
    }
    ctx.result = switch (outcome) {
      SyncSuccess() => SyncJobResult.succeeded,
      SyncRetryable() => SyncJobResult.retryable,
      SyncUnrecoverable() => SyncJobResult.rejected,
      SyncConflict() => SyncJobResult.conflict,
    };
    return DataPipeline.success(input: ctx, output: ctx);
  }
}
