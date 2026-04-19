import 'package:leulit_flutter_actionmanager/leulit_flutter_actionmanager.dart';

import 'contracts/sync_job.dart';

class EntityQueuedEvent {
  final String entityType;
  final String entityId;
  final SyncOperation operation;

  const EntityQueuedEvent({
    required this.entityType,
    required this.entityId,
    required this.operation,
  });
}

class EntitySyncedEvent {
  final String entityType;
  final String entityId;
  final SyncOperation operation;
  final String? remoteId;

  const EntitySyncedEvent({
    required this.entityType,
    required this.entityId,
    required this.operation,
    this.remoteId,
  });
}

class EntityFailedEvent {
  final String entityType;
  final String entityId;
  final SyncOperation operation;
  final String error;
  final bool retryable;

  const EntityFailedEvent({
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.error,
    required this.retryable,
  });
}

class EntityConflictEvent {
  final String entityType;
  final String entityId;

  const EntityConflictEvent({
    required this.entityType,
    required this.entityId,
  });
}

class SyncFinishedEvent {
  final int processed;
  final int failed;
  final int remainingPending;

  const SyncFinishedEvent({
    required this.processed,
    required this.failed,
    required this.remainingPending,
  });
}

abstract class SyncActions {
  static const connectionRestored =
      TypedAction<void>('SyncActions.connectionRestored');
  static const connectionLost =
      TypedAction<void>('SyncActions.connectionLost');

  static const entityQueued =
      TypedAction<EntityQueuedEvent>('SyncActions.entityQueued');
  static const entitySynced =
      TypedAction<EntitySyncedEvent>('SyncActions.entitySynced');
  static const entityFailed =
      TypedAction<EntityFailedEvent>('SyncActions.entityFailed');
  static const entityConflict =
      TypedAction<EntityConflictEvent>('SyncActions.entityConflict');

  static const syncStarted = TypedAction<void>('SyncActions.syncStarted');
  static const syncFinished =
      TypedAction<SyncFinishedEvent>('SyncActions.syncFinished');

  static const backgroundSyncRequested =
      TypedAction<void>('SyncActions.backgroundSyncRequested');
}
