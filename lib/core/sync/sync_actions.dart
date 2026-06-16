import 'package:leulit_flutter_actionmanager/leulit_flutter_actionmanager.dart';

import 'contracts/sync_job.dart';
import 'pull/pull_outcome.dart';

class EntityQueuedEvent {
  final String entityType;
  final String clientId;
  final SyncOperation operation;

  const EntityQueuedEvent({
    required this.entityType,
    required this.clientId,
    required this.operation,
  });
}

class EntitySyncedEvent {
  final String entityType;
  final String clientId;
  final SyncOperation operation;
  final String? remoteId;

  const EntitySyncedEvent({
    required this.entityType,
    required this.clientId,
    required this.operation,
    this.remoteId,
  });
}

class EntityRejectedEvent {
  final String entityType;
  final String clientId;
  final SyncOperation operation;
  final String? errorMessageEs;
  final int? statusCode;

  const EntityRejectedEvent({
    required this.entityType,
    required this.clientId,
    required this.operation,
    this.errorMessageEs,
    this.statusCode,
  });
}

class EntityConflictEvent {
  final String entityType;
  final String clientId;

  const EntityConflictEvent({
    required this.entityType,
    required this.clientId,
  });
}

class CloudPullCompletedEvent {
  final String entityType;
  final int upserted;
  final int conflicts;
  final bool cancelled;
  final PullOutcome outcome;
  final String? errorMessage;

  const CloudPullCompletedEvent({
    required this.entityType,
    required this.upserted,
    required this.conflicts,
    required this.cancelled,
    required this.outcome,
    this.errorMessage,
  });
}

abstract class SyncActions {
  /// Informational events emitted by `ConnectivityService` so the UI can show
  /// online/offline badges. They do NOT trigger any sync activity — drain
  /// happens exclusively when the user requests it.
  static const connectionRestored =
      TypedAction<void>('SyncActions.connectionRestored');
  static const connectionLost =
      TypedAction<void>('SyncActions.connectionLost');

  static const entityQueued =
      TypedAction<EntityQueuedEvent>('SyncActions.entityQueued');

  static const entitySynced =
      TypedAction<EntitySyncedEvent>('SyncActions.entitySynced');

  static const entityRejected =
      TypedAction<EntityRejectedEvent>('SyncActions.entityRejected');

  static const entityConflict =
      TypedAction<EntityConflictEvent>('SyncActions.entityConflict');

  static const cloudPullCompleted =
      TypedAction<CloudPullCompletedEvent>('SyncActions.cloudPullCompleted');

  static const authExpired = TypedAction<void>('SyncActions.authExpired');
}
