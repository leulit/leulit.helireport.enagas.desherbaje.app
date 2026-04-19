import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../contracts/local_store.dart';
import '../contracts/sync_job.dart';
import '../contracts/syncable.dart';
import '../engine/sync_engine.dart';
import '../outbox/outbox_queue.dart';
import '../sync_actions.dart';

class OfflineRepository<T extends Syncable> {
  final String entityType;
  final Database _db;
  final LocalStore<T> _store;
  final OutboxQueue _outbox;
  final SyncEngine _engine;
  final bool Function() _isOnline;

  OfflineRepository({
    required this.entityType,
    required Database db,
    required LocalStore<T> store,
    required OutboxQueue outbox,
    required SyncEngine engine,
    required bool Function() isOnline,
  })  : _db = db,
        _store = store,
        _outbox = outbox,
        _engine = engine,
        _isOnline = isOnline;

  Future<void> create(T entity) =>
      _persistAndEnqueue(entity, SyncOperation.create);

  Future<void> update(T entity) =>
      _persistAndEnqueue(entity, SyncOperation.update);

  Future<void> delete(T entity) async {
    await _db.transaction((txn) async {
      await _store.delete(entity.clientId, txn: txn);
      await _outbox.enqueue(
        entityType: entityType,
        entityId: entity.clientId,
        operation: SyncOperation.delete,
        payload: jsonEncode(entity.toJson()),
        txn: txn,
      );
    });
    SyncActions.entityQueued.dispatch(
      data: EntityQueuedEvent(
        entityType: entityType,
        entityId: entity.clientId,
        operation: SyncOperation.delete,
      ),
    );
    _triggerDrain();
  }

  Future<T?> findByClientId(String clientId) =>
      _store.findByClientId(clientId);

  Future<List<T>> findAll() => _store.findAll();

  Future<void> _persistAndEnqueue(T entity, SyncOperation op) async {
    await _db.transaction((txn) async {
      await _store.upsert(entity, txn: txn);
      await _outbox.enqueue(
        entityType: entityType,
        entityId: entity.clientId,
        operation: op,
        payload: jsonEncode(entity.toJson()),
        txn: txn,
      );
    });
    SyncActions.entityQueued.dispatch(
      data: EntityQueuedEvent(
        entityType: entityType,
        entityId: entity.clientId,
        operation: op,
      ),
    );
    _triggerDrain();
  }

  void _triggerDrain() {
    if (!_isOnline()) return;
    unawaited(_engine.drain());
  }
}
