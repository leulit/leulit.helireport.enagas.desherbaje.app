import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/app_log.dart';
import '../../core/sync/contracts/local_store.dart';
import '../../domain/entities/position_batch_entity.dart';

/// Persists GPS batches by storing one row per point in `posiciones_gps`,
/// each row carrying the `batch_client_id` of its batch. Keeps storage
/// compact (no JSON blobs) and lets each batch be reconstructed by
/// grouping rows on `batch_client_id`.
class PositionLocalStore implements LocalStore<PositionBatchEntity> {
  static const String _tablePoints = 'posiciones_gps';
  static const String _tableBatches = 'posiciones_gps_batches';

  final Database _db;

  PositionLocalStore(this._db);

  @override
  String get entityType => 'position_batch';

  @override
  int get schemaVersion => 1;

  @override
  Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    if (from == 0 && to == 1) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableBatches (
          batch_client_id TEXT PRIMARY KEY,
          remote_id       INTEGER,
          operador_id     INTEGER NOT NULL,
          started_at      TEXT    NOT NULL,
          ended_at        TEXT    NOT NULL,
          updated_at      TEXT    NOT NULL,
          synced_at       TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tablePoints (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          batch_client_id TEXT    NOT NULL,
          captured_at     TEXT    NOT NULL,
          lat             REAL    NOT NULL,
          lng             REAL    NOT NULL,
          accuracy_m      REAL,
          altitude_m      REAL,
          speed_mps       REAL,
          FOREIGN KEY (batch_client_id) REFERENCES $_tableBatches(batch_client_id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${_tablePoints}_batch '
        'ON $_tablePoints(batch_client_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${_tablePoints}_time '
        'ON $_tablePoints(captured_at)',
      );
    }
  }

  @override
  Future<void> upsert(
    PositionBatchEntity entity, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? _db;
    if (executor is Database) {
      await executor.transaction((tx) => _upsertWith(tx, entity));
      return;
    }
    await _upsertWith(executor, entity);
  }

  Future<void> _upsertWith(
    DatabaseExecutor executor,
    PositionBatchEntity entity,
  ) async {
    await executor.insert(
      _tableBatches,
      {
        'batch_client_id': entity.clientId,
        'remote_id': entity.id,
        'operador_id': entity.operadorId,
        'started_at': entity.startedAt.toIso8601String(),
        'ended_at': entity.endedAt.toIso8601String(),
        'updated_at': entity.updatedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Replace points wholesale so re-saving the same batch is idempotent.
    await executor.delete(
      _tablePoints,
      where: 'batch_client_id = ?',
      whereArgs: [entity.clientId],
    );
    final batch = executor.batch();
    for (final p in entity.points) {
      batch.insert(_tablePoints, {
        'batch_client_id': entity.clientId,
        'captured_at': p.capturedAt.toIso8601String(),
        'lat': p.lat,
        'lng': p.lng,
        'accuracy_m': p.accuracyMeters,
        'altitude_m': p.altitudeMeters,
        'speed_mps': p.speedMps,
      });
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> delete(String clientId, {DatabaseExecutor? txn}) async {
    final executor = txn ?? _db;
    await executor.delete(
      _tableBatches,
      where: 'batch_client_id = ?',
      whereArgs: [clientId],
    );
    // Cascade is on but cover non-FK databases too.
    await executor.delete(
      _tablePoints,
      where: 'batch_client_id = ?',
      whereArgs: [clientId],
    );
  }

  /// Push-only store — position batches are never pulled from the backend, so
  /// there is no remote-id lookup path. Always returns `null`.
  @override
  Future<PositionBatchEntity?> findByRemoteId(String remoteId) async => null;

  @override
  Future<PositionBatchEntity?> findByClientId(String clientId) async {
    final batchRows = await _db.query(
      _tableBatches,
      where: 'batch_client_id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (batchRows.isEmpty) return null;
    final batchRow = batchRows.first;
    final pointsRows = await _db.query(
      _tablePoints,
      where: 'batch_client_id = ?',
      whereArgs: [clientId],
      orderBy: 'captured_at ASC',
    );
    return _toEntity(batchRow, pointsRows);
  }

  /// NF-23: 2 queries instead of N+1.
  /// One query for all batches (DESC by started_at) + one for all points
  /// (ASC by captured_at) + group in memory by batch_client_id.
  @override
  Future<List<PositionBatchEntity>> findAll() async {
    final batchRows = await _db.query(
      _tableBatches,
      orderBy: 'started_at DESC',
    );
    if (batchRows.isEmpty) return const [];

    // Single query for all points across all batches; order ASC is per-batch
    // because we group them and each batch's slice will already be ordered.
    final allPointRows = await _db.query(
      _tablePoints,
      orderBy: 'captured_at ASC',
    );

    // Group points by batch_client_id in O(n).
    final pointsByBatch = <String, List<Map<String, Object?>>>{};
    for (final row in allPointRows) {
      final key = row['batch_client_id']! as String;
      (pointsByBatch[key] ??= []).add(row);
    }

    return batchRows
        .map((row) {
          final clientId = row['batch_client_id']! as String;
          return _toEntity(row, pointsByBatch[clientId] ?? const []);
        })
        .toList();
  }

  @override
  Future<void> markSynced({
    required String clientId,
    String? remoteId,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? _db;
    final updates = <String, Object?>{
      'synced_at': DateTime.now().toIso8601String(),
    };
    if (remoteId != null) {
      final asInt = int.tryParse(remoteId);
      if (asInt != null) updates['remote_id'] = asInt;
    }
    await executor.update(
      _tableBatches,
      updates,
      where: 'batch_client_id = ?',
      whereArgs: [clientId],
    );
  }

  /// Deletes points and batches whose `synced_at` is older than [cutoff].
  /// Returns the number of batch rows removed. Backed batches are the
  /// retention unit; their points cascade.
  Future<int> purgeSyncedBefore(DateTime cutoff) async {
    final cutoffIso = cutoff.toIso8601String();
    return _db.delete(
      _tableBatches,
      where: 'synced_at IS NOT NULL AND synced_at < ?',
      whereArgs: [cutoffIso],
    );
  }

  PositionBatchEntity _toEntity(
    Map<String, Object?> batchRow,
    List<Map<String, Object?>> pointsRows,
  ) {
    final endedAt = DateTime.parse(batchRow['ended_at']! as String);

    // NF-24: if updated_at doesn't parse, do NOT fall through to
    // DateTime.now() (the constructor default). Use a deterministic fallback
    // (endedAt, already parsed) and log the bad value so it's observable.
    final rawUpdatedAt = batchRow['updated_at'];
    DateTime? updatedAt;
    if (rawUpdatedAt != null) {
      updatedAt = DateTime.tryParse(rawUpdatedAt as String);
      if (updatedAt == null) {
        if (kDebugMode) {
          AppLog.w(
            'PositionLocalStore: unparseable updated_at="$rawUpdatedAt" '
            'for batch ${batchRow['batch_client_id']}; falling back to endedAt.',
          );
        }
        updatedAt = endedAt; // deterministic fallback
      }
    }

    return PositionBatchEntity(
      clientId: batchRow['batch_client_id']! as String,
      id: batchRow['remote_id'] as int?,
      operadorId: (batchRow['operador_id'] as int?) ?? 0,
      startedAt: DateTime.parse(batchRow['started_at']! as String),
      endedAt: endedAt,
      updatedAt: updatedAt,
      points: pointsRows
          .map((r) => PositionPoint(
                capturedAt: DateTime.parse(r['captured_at']! as String),
                lat: (r['lat'] as num).toDouble(),
                lng: (r['lng'] as num).toDouble(),
                accuracyMeters: (r['accuracy_m'] as num?)?.toDouble(),
                altitudeMeters: (r['altitude_m'] as num?)?.toDouble(),
                speedMps: (r['speed_mps'] as num?)?.toDouble(),
              ))
          .toList(),
    );
  }
}
