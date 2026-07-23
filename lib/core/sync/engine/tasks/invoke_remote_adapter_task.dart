import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

import '../../contracts/auth_expired_exception.dart';
import '../../contracts/remote_adapter.dart';
import '../../contracts/sync_cancelled_exception.dart';
import '../sync_job_context.dart';

/// Calls the registration's [RemoteAdapter.push] for the entity in the
/// context. Translates uncaught exceptions into [SyncRetryable] outcomes
/// (transport hiccups) but lets [AuthExpiredException] propagate so the
/// engine can abort the whole drain.
///
/// Blocking: an [AuthExpiredException] thrown here propagates as the
/// pipeline failure that the engine recognises to abort the drain.
class InvokeRemoteAdapterTask extends PipelineTask<SyncJobContext> {
  @override
  String get name => 'InvokeRemoteAdapter';

  @override
  bool get isBlocking => true;

  @override
  Future<DataPipeline<SyncJobContext>> execute(
    DataPipeline<SyncJobContext> data,
  ) async {
    final ctx = data.output;
    final adapter = ctx.registration.adapter;
    if (adapter == null) {
      return DataPipeline.error(
        input: ctx,
        error: StateError(
          'Type ${ctx.job.entityType} has no RemoteAdapter — push attempted '
          'on a read-only entity.',
        ),
      );
    }
    final entity = ctx.entity;
    if (entity == null) {
      return DataPipeline.error(
        input: ctx,
        error: StateError('Entity not loaded before InvokeRemoteAdapter'),
      );
    }
    try {
      ctx.outcome = await adapter.push(
        entity: entity,
        operation: ctx.job.operation,
        token: ctx.token,
        onProgress: ctx.onProgress,
      );
    } on AuthExpiredException {
      rethrow;
    } on SyncCancelledException {
      // Cancelar no es fallar: se propaga para que el motor devuelva el job a
      // `pending`. Tragarlo aquí lo convertiría en un SyncRetryable con un
      // `last_error` que mentiría sobre la causa.
      rethrow;
    } catch (e) {
      ctx.outcome = SyncRetryable('Uncaught: $e');
    }
    return DataPipeline.success(input: ctx, output: ctx);
  }
}
