import 'dart:async';
import 'dart:convert';

import '../contracts/remote_adapter.dart';
import '../contracts/sync_job.dart';
import '../contracts/syncable.dart';
import '../outbox/outbox_queue.dart';
import '../sync_actions.dart';
import '../type_registry.dart';

class SyncEngineConfig {
  final int batchSize;
  final int maxAttempts;

  const SyncEngineConfig({
    this.batchSize = 5,
    this.maxAttempts = 5,
  });
}

class SyncEngine {
  final OutboxQueue _outbox;
  final TypeRegistry _registry;
  final SyncEngineConfig _config;
  final bool Function() _isOnline;

  String? _connectionRestoredHandlerId;
  String? _backgroundSyncHandlerId;
  bool _isDraining = false;

  SyncEngine({
    required OutboxQueue outbox,
    required TypeRegistry registry,
    required bool Function() isOnline,
    SyncEngineConfig config = const SyncEngineConfig(),
  })  : _outbox = outbox,
        _registry = registry,
        _isOnline = isOnline,
        _config = config;

  bool get isDraining => _isDraining;

  void start() {
    _connectionRestoredHandlerId ??= SyncActions.connectionRestored.on(
      (_) => drain(),
      debugLabel: 'SyncEngine.onConnectionRestored',
    );
    _backgroundSyncHandlerId ??= SyncActions.backgroundSyncRequested.on(
      (_) => drain(),
      debugLabel: 'SyncEngine.onBackgroundSyncRequested',
    );
  }

  void stop() {
    final restoredId = _connectionRestoredHandlerId;
    if (restoredId != null) {
      SyncActions.connectionRestored.off(restoredId);
      _connectionRestoredHandlerId = null;
    }
    final bgId = _backgroundSyncHandlerId;
    if (bgId != null) {
      SyncActions.backgroundSyncRequested.off(bgId);
      _backgroundSyncHandlerId = null;
    }
  }

  Future<SyncFinishedEvent?> drain() async {
    if (_isDraining) return null;
    if (!_isOnline()) return null;

    _isDraining = true;
    SyncActions.syncStarted.dispatch();

    var processed = 0;
    var failed = 0;

    try {
      while (_isOnline()) {
        final batch = await _outbox.nextPending(limit: _config.batchSize);
        if (batch.isEmpty) break;

        for (final job in batch) {
          if (!_isOnline()) break;
          final ok = await _processOne(job);
          if (ok) {
            processed++;
          } else {
            failed++;
          }
        }
      }
    } finally {
      _isDraining = false;
    }

    final remaining = await _outbox.countPending();
    final event = SyncFinishedEvent(
      processed: processed,
      failed: failed,
      remainingPending: remaining,
    );
    SyncActions.syncFinished.dispatch(data: event);
    return event;
  }

  Future<bool> _processOne(SyncJob job) async {
    final registration = _registry.lookup(job.entityType);
    if (registration == null) {
      await _outbox.markDead(
        job.id,
        reason: 'No registration for entity type "${job.entityType}"',
      );
      _emitFailed(job, 'No registration', retryable: false);
      return false;
    }

    Syncable entity;
    try {
      entity = _deserialize(registration, job);
    } catch (e) {
      await _outbox.markDead(job.id, reason: 'Deserialize failed: $e');
      _emitFailed(job, 'Deserialize failed: $e', retryable: false);
      return false;
    }

    await _outbox.markSyncing(job.id);
    final currentAttempts = (await _outbox.byId(job.id))?.attempts ?? 1;

    try {
      final outcome = await registration.adapter.push(
        entity: entity,
        operation: job.operation,
      );
      return _handleOutcome(job, outcome, currentAttempts, registration);
    } catch (e) {
      return _handleRetryable(job, 'Uncaught: $e', currentAttempts);
    }
  }

  Syncable _deserialize(TypeRegistration<Syncable> reg, SyncJob job) {
    final raw = job.payload;
    if (raw == null || raw.isEmpty) {
      throw StateError('Job ${job.id} has no payload');
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return reg.fromJson(map);
  }

  Future<bool> _handleOutcome(
    SyncJob job,
    SyncOutcome<Syncable> outcome,
    int attempts,
    TypeRegistration<Syncable> registration,
  ) async {
    switch (outcome) {
      case SyncSuccess(:final remoteId, :final serverVersion):
        await _outbox.markSynced(job.id, remoteId: remoteId);
        if (job.operation == SyncOperation.delete) {
          await registration.localStore?.delete(job.entityId);
        } else {
          if (serverVersion != null) {
            await registration.localStore?.upsert(serverVersion);
          }
          await registration.localStore?.markSynced(
            clientId: job.entityId,
            remoteId: remoteId,
          );
        }
        SyncActions.entitySynced.dispatch(
          data: EntitySyncedEvent(
            entityType: job.entityType,
            entityId: job.entityId,
            operation: job.operation,
            remoteId: remoteId,
          ),
        );
        return true;

      case SyncRetryable(:final reason):
        return _handleRetryable(job, reason, attempts);

      case SyncUnrecoverable(:final reason):
        await _outbox.markDead(job.id, reason: reason);
        _emitFailed(job, reason, retryable: false);
        return false;

      case SyncConflict():
        await _outbox.markDead(job.id, reason: 'Conflict');
        SyncActions.entityConflict.dispatch(
          data: EntityConflictEvent(
            entityType: job.entityType,
            entityId: job.entityId,
          ),
        );
        return false;
    }
  }

  Future<bool> _handleRetryable(
    SyncJob job,
    String reason,
    int attempts,
  ) async {
    if (attempts >= _config.maxAttempts) {
      await _outbox.markDead(
        job.id,
        reason: 'Max attempts reached: $reason',
      );
      _emitFailed(job, reason, retryable: false);
      return false;
    }
    await _outbox.markPending(job.id, error: reason);
    _emitFailed(job, reason, retryable: true);
    return false;
  }

  void _emitFailed(SyncJob job, String reason, {required bool retryable}) {
    SyncActions.entityFailed.dispatch(
      data: EntityFailedEvent(
        entityType: job.entityType,
        entityId: job.entityId,
        operation: job.operation,
        error: reason,
        retryable: retryable,
      ),
    );
  }
}
