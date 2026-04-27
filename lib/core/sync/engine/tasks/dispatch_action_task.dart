import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

import '../../contracts/remote_adapter.dart';
import '../../sync_actions.dart';
import '../sync_job_context.dart';

/// Final task in the per-job pipeline: emits the appropriate [TypedAction]
/// so any UI / service listening can react.
class DispatchActionTask extends PipelineTask<SyncJobContext> {
  @override
  String get name => 'DispatchAction';

  @override
  bool get isBlocking => false;

  @override
  Future<DataPipeline<SyncJobContext>> execute(
    DataPipeline<SyncJobContext> data,
  ) async {
    final ctx = data.output;
    final job = ctx.job;

    switch (ctx.outcome!) {
      case SyncSuccess(:final remoteId):
        SyncActions.entitySynced.dispatch(
          data: EntitySyncedEvent(
            entityType: job.entityType,
            clientId: job.clientId,
            operation: job.operation,
            remoteId: remoteId,
          ),
        );

      case SyncRetryable():
        // Retryable does not dispatch — the user will see counts in the UI;
        // we don't want to spam listeners on transient network blips.
        break;

      case SyncUnrecoverable(:final statusCode, :final errorMessageEs, :final reason):
        SyncActions.entityRejected.dispatch(
          data: EntityRejectedEvent(
            entityType: job.entityType,
            clientId: job.clientId,
            operation: job.operation,
            errorMessageEs: errorMessageEs ?? reason,
            statusCode: statusCode,
          ),
        );

      case SyncConflict():
        SyncActions.entityConflict.dispatch(
          data: EntityConflictEvent(
            entityType: job.entityType,
            clientId: job.clientId,
          ),
        );
    }
    return DataPipeline.success(input: ctx, output: ctx);
  }
}
