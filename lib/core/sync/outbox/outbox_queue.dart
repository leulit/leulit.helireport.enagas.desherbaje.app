import 'package:sqflite/sqflite.dart';

import '../contracts/sync_job.dart';
import '../database/offline_database.dart';
import '../sync_actions.dart';

/// Persistent operation queue for the sync engine.
///
/// Stores rows of pending writes (`create | update | delete`) per entity.
/// The engine drains the queue manually (no automatic retry, no backoff,
/// no expiration) when the user asks for it.
class OutboxQueue {
  static const _table = OfflineDatabase.syncQueueTable;

  final Database _db;

  OutboxQueue(this._db);

  /// Enqueues an operation. Idempotent on the unique
  /// `(entity_type, client_id, operation)` triple.
  ///
  /// On conflict (re-enqueue of the same triple) the row is updated in-place:
  /// `status → pending`, `attempts → 0`, `last_error/status_code → NULL`.
  /// Crucially, `remote_id`, `synced_at`, and `created_at` are **preserved**
  /// so that a re-edit of an already-synced entity does not lose its server id.
  Future<int> enqueue({
    required String entityType,
    required String clientId,
    required SyncOperation operation,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await executor.rawInsert('''
      INSERT INTO $_table
        (entity_type, client_id, operation, status, attempts,
         last_error, status_code, created_at)
      VALUES (?, ?, ?, ?, 0, NULL, NULL, ?)
      ON CONFLICT(entity_type, client_id, operation) DO UPDATE SET
        status      = 'pending',
        attempts    = 0,
        last_error  = NULL,
        status_code = NULL
    ''', [entityType, clientId, operation.wireName, SyncStatus.pending.wireName, now]);

    final rows = await executor.rawQuery(
      'SELECT id FROM $_table WHERE entity_type=? AND client_id=? AND operation=?',
      [entityType, clientId, operation.wireName],
    );
    final id = rows.first['id'] as int;

    SyncActions.entityQueued.dispatch(
      data: EntityQueuedEvent(
        entityType: entityType,
        clientId: clientId,
        operation: operation,
      ),
    );
    return id;
  }

  /// Returns up to [limit] pending jobs in FIFO order, optionally filtered by
  /// [entityType] and by [onlyClientIds] (scoped drain of a single segmento's
  /// jobs). An empty [onlyClientIds] is treated as "no filter"; callers that
  /// mean "nothing to drain" must skip the call entirely.
  Future<List<SyncJob>> nextPending({
    String? entityType,
    int limit = 100,
    Set<String>? onlyClientIds,
  }) async {
    final conditions = <String>['status = ?'];
    final args = <Object?>[SyncStatus.pending.wireName];
    if (entityType != null) {
      conditions.add('entity_type = ?');
      args.add(entityType);
    }
    if (onlyClientIds != null && onlyClientIds.isNotEmpty) {
      final placeholders = List.filled(onlyClientIds.length, '?').join(', ');
      conditions.add('client_id IN ($placeholders)');
      args.addAll(onlyClientIds);
    }
    final rows = await _db.query(
      _table,
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
    return rows.map(SyncJob.fromRow).toList(growable: false);
  }

  Future<List<SyncJob>> pendingJobs({String? entityType}) =>
      _allWithStatus(SyncStatus.pending, entityType: entityType);

  Future<List<SyncJob>> rejectedJobs({String? entityType}) =>
      _allWithStatus(SyncStatus.rejected, entityType: entityType);

  /// Returns all jobs currently being drained (status=syncing), optionally
  /// filtered by [entityType]. Used by [DetectConflictsTask] so that a pull
  /// concurrent with a drain does not classify a `syncing` clientId as safe to
  /// upsert — avoiding a race that would overwrite an edit being pushed.
  Future<List<SyncJob>> syncingJobs({String? entityType}) =>
      _allWithStatus(SyncStatus.syncing, entityType: entityType);

  /// Jobs ya entregados (status=synced). Llevan `syncedAt`, que es lo que
  /// permite distinguir lo que se subió dentro de un intento ya cerrado de lo
  /// que se subió en uno que quedó abierto.
  Future<List<SyncJob>> syncedJobs({String? entityType}) =>
      _allWithStatus(SyncStatus.synced, entityType: entityType);

  Future<int> countPending({String? entityType}) =>
      _countByStatus(SyncStatus.pending, entityType: entityType);

  Future<int> countRejected({String? entityType}) =>
      _countByStatus(SyncStatus.rejected, entityType: entityType);

  Future<SyncJob?> byId(int jobId) async {
    final rows = await _db.query(
      _table,
      where: 'id = ?',
      whereArgs: [jobId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SyncJob.fromRow(rows.first);
  }

  Future<void> markSyncing(int jobId) async {
    final current = await byId(jobId);
    final attempts = (current?.attempts ?? 0) + 1;
    await _db.update(
      _table,
      {
        'status': SyncStatus.syncing.wireName,
        'attempts': attempts,
      },
      where: 'id = ?',
      whereArgs: [jobId],
    );
  }

  Future<void> markSynced(int jobId, {String? remoteId}) async {
    await _db.update(
      _table,
      {
        'status': SyncStatus.synced.wireName,
        'synced_at': DateTime.now().millisecondsSinceEpoch,
        'remote_id': remoteId,
        'last_error': null,
        'status_code': null,
      },
      where: 'id = ?',
      whereArgs: [jobId],
    );
  }

  Future<void> markPendingAgain(
    int jobId, {
    required String error,
    int? statusCode,
  }) async {
    await _db.update(
      _table,
      {
        'status': SyncStatus.pending.wireName,
        'last_error': error,
        'status_code': statusCode,
      },
      where: 'id = ?',
      whereArgs: [jobId],
    );
  }

  Future<void> markRejected(
    int jobId, {
    required String error,
    int? statusCode,
  }) async {
    await _db.update(
      _table,
      {
        'status': SyncStatus.rejected.wireName,
        'last_error': error,
        'status_code': statusCode,
      },
      where: 'id = ?',
      whereArgs: [jobId],
    );
  }

  /// Promotes a rejected job back to pending so the user can retry it.
  Future<void> retryRejected(int jobId) async {
    await _db.update(
      _table,
      {
        'status': SyncStatus.pending.wireName,
        'last_error': null,
        'status_code': null,
      },
      where: 'id = ? AND status = ?',
      whereArgs: [jobId, SyncStatus.rejected.wireName],
    );
  }

  /// Removes a job from the queue (used by "Descartar" in the UI).
  Future<void> discardJob(int jobId) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: [jobId]);
  }

  /// Removes any pending job referencing the given entity. Called when the
  /// repository deletes the local row before any push has succeeded.
  Future<void> removeForEntity({
    required String entityType,
    required String clientId,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? _db;
    await executor.delete(
      _table,
      where: 'entity_type = ? AND client_id = ?',
      whereArgs: [entityType, clientId],
    );
  }

  /// Garbage-collects long-since synced rows. Default 7 days.
  Future<int> purgeSynced({Duration olderThan = const Duration(days: 7)}) async {
    final threshold =
        DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
    return _db.delete(
      _table,
      where: 'status = ? AND synced_at IS NOT NULL AND synced_at < ?',
      whereArgs: [SyncStatus.synced.wireName, threshold],
    );
  }

  Future<List<SyncJob>> _allWithStatus(
    SyncStatus status, {
    String? entityType,
  }) async {
    final rows = await _db.query(
      _table,
      where: entityType == null
          ? 'status = ?'
          : 'status = ? AND entity_type = ?',
      whereArgs: entityType == null
          ? [status.wireName]
          : [status.wireName, entityType],
      orderBy: 'created_at DESC',
    );
    return rows.map(SyncJob.fromRow).toList(growable: false);
  }

  Future<int> _countByStatus(SyncStatus status, {String? entityType}) async {
    final result = await _db.rawQuery(
      entityType == null
          ? 'SELECT COUNT(*) AS c FROM $_table WHERE status = ?'
          : 'SELECT COUNT(*) AS c FROM $_table WHERE status = ? AND entity_type = ?',
      entityType == null ? [status.wireName] : [status.wireName, entityType],
    );
    return (result.first['c'] as int?) ?? 0;
  }
}
