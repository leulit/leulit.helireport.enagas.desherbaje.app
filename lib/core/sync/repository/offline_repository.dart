import 'package:sqflite/sqflite.dart';

import '../contracts/local_store.dart';
import '../contracts/sync_job.dart';
import '../contracts/syncable.dart';
import '../outbox/outbox_queue.dart';

/// Generic CRUD façade over a [LocalStore] + [OutboxQueue] pair.
///
/// Writes always land in the local store first, then enqueue a sync job.
/// Reads are on-demand from the local store (no streams, no caching).
///
/// **Does not trigger sync.** Drains happen exclusively when the user asks
/// for them through the sync page or per-entity buttons.
class OfflineRepository<T extends Syncable> {
  final String entityType;
  final Database _db;
  final LocalStore<T> _store;
  final OutboxQueue _outbox;

  OfflineRepository({
    required this.entityType,
    required Database db,
    required LocalStore<T> store,
    required OutboxQueue outbox,
  })  : _db = db,
        _store = store,
        _outbox = outbox;

  Future<void> create(T entity) =>
      _persistAndEnqueue(entity, SyncOperation.create);

  Future<void> update(T entity) =>
      _persistAndEnqueue(entity, SyncOperation.update);

  Future<void> delete(T entity) async {
    await _db.transaction((txn) async {
      await _store.delete(entity.clientId, txn: txn);
      await _outbox.enqueue(
        entityType: entityType,
        clientId: entity.clientId,
        operation: SyncOperation.delete,
        txn: txn,
      );
    });
  }

  /// Deletes an entity that has never been pushed: removes the local row and
  /// purges any pending outbox job for it (no remote delete is enqueued). Use
  /// for user-initiated deletion of not-yet-synced captures.
  Future<void> purgeLocal(T entity) async {
    await _db.transaction((txn) async {
      await _store.delete(entity.clientId, txn: txn);
      await _outbox.removeForEntity(
        entityType: entityType,
        clientId: entity.clientId,
        txn: txn,
      );
    });
  }

  Future<T?> findByClientId(String clientId) =>
      _store.findByClientId(clientId);

  Future<List<T>> findAll() => _store.findAll();

  Future<List<T>> findWhere(String column, Object? value) =>
      _store.findWhere(column, value);

  Future<void> _persistAndEnqueue(T entity, SyncOperation op) async {
    await _db.transaction((txn) async {
      await _store.upsert(entity, txn: txn);
      await _outbox.enqueue(
        entityType: entityType,
        clientId: entity.clientId,
        operation: op,
        txn: txn,
      );
    });
  }
}
