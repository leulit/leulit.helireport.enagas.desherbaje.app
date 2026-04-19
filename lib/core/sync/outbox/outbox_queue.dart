import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../contracts/sync_job.dart';
import 'outbox_schema.dart';

class OutboxQueue {
  final Database _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  OutboxQueue(this._db);

  Stream<void> get changes => _changes.stream;

  Future<int> enqueue({
    required String entityType,
    required String entityId,
    required SyncOperation operation,
    String? payload,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? _db;
    final id = await executor.insert(
      OutboxSchema.tableName,
      {
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': operation.wireName,
        'status': SyncStatus.pending.wireName,
        'attempts': 0,
        'payload': payload,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
    return id;
  }

  Future<List<SyncJob>> nextPending({int limit = 5}) async {
    final rows = await _db.query(
      OutboxSchema.tableName,
      where: 'status = ?',
      whereArgs: [SyncStatus.pending.wireName],
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
    return rows.map(SyncJob.fromRow).toList(growable: false);
  }

  Future<int> countPending() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${OutboxSchema.tableName} '
      'WHERE status IN (?, ?)',
      [SyncStatus.pending.wireName, SyncStatus.syncing.wireName],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<int> countByStatus(SyncStatus status) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${OutboxSchema.tableName} WHERE status = ?',
      [status.wireName],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<List<SyncJob>> allWithStatus(SyncStatus status) async {
    final rows = await _db.query(
      OutboxSchema.tableName,
      where: 'status = ?',
      whereArgs: [status.wireName],
      orderBy: 'created_at DESC',
    );
    return rows.map(SyncJob.fromRow).toList(growable: false);
  }

  Future<SyncJob?> byId(int id) async {
    final rows = await _db.query(
      OutboxSchema.tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SyncJob.fromRow(rows.first);
  }

  Future<void> markSyncing(int id) async {
    await _db.update(
      OutboxSchema.tableName,
      {
        'status': SyncStatus.syncing.wireName,
        'attempts': await _incrementedAttempts(id),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  Future<void> markSynced(int id, {String? remoteId}) async {
    await _db.update(
      OutboxSchema.tableName,
      {
        'status': SyncStatus.synced.wireName,
        'synced_at': DateTime.now().millisecondsSinceEpoch,
        'remote_id': remoteId,
        'last_error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  Future<void> markPending(int id, {required String error}) async {
    await _db.update(
      OutboxSchema.tableName,
      {
        'status': SyncStatus.pending.wireName,
        'last_error': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  Future<void> markDead(int id, {required String reason}) async {
    await _db.update(
      OutboxSchema.tableName,
      {
        'status': SyncStatus.dead.wireName,
        'last_error': reason,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  Future<void> removeForEntity({
    required String entityType,
    required String entityId,
  }) async {
    await _db.delete(
      OutboxSchema.tableName,
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
    );
    _notify();
  }

  Future<void> delete(int id) async {
    await _db.delete(
      OutboxSchema.tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  Future<int> purgeSynced({Duration olderThan = const Duration(days: 7)}) async {
    final threshold =
        DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
    final deleted = await _db.delete(
      OutboxSchema.tableName,
      where: 'status = ? AND synced_at IS NOT NULL AND synced_at < ?',
      whereArgs: [SyncStatus.synced.wireName, threshold],
    );
    if (deleted > 0) _notify();
    return deleted;
  }

  Future<int> _incrementedAttempts(int id) async {
    final row = await byId(id);
    return (row?.attempts ?? 0) + 1;
  }

  void _notify() {
    if (_changes.isClosed) return;
    _changes.add(null);
  }

  Future<void> dispose() async {
    await _changes.close();
  }
}
