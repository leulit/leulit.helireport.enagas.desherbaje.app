import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/app_log.dart';
import '../../core/sync/contracts/local_store.dart';
import '../../domain/entities/traza_entity.dart';

/// Persists trazas (manual GPS tracks) as one header row in `trazas` + one
/// row per point in `trazas_puntos`, mirroring the `posiciones_gps` layout.
///
/// Beyond the [LocalStore] contract, exposes the operations the recording
/// feature actually needs: [appendPoints] (hot path, append-only — never
/// use [upsert] while a traza is recording, it replaces the points
/// wholesale), [findOpen] / [findAnyOpen] (recovery), [finalize] (close a
/// traza) and [deleteSynced] (retention).
class TrazaLocalStore implements LocalStore<TrazaEntity> {
  static const String _tableTrazas = 'trazas';
  static const String _tablePuntos = 'trazas_puntos';

  final Database _db;

  TrazaLocalStore(this._db);

  @override
  String get entityType => 'traza';

  @override
  int get schemaVersion => 1;

  @override
  Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    if (from == 0 && to == 1) {
      // App not yet in production: drop the legacy position_batch tables
      // instead of migrating them.
      await db.execute('DROP TABLE IF EXISTS posiciones_gps');
      await db.execute('DROP TABLE IF EXISTS posiciones_gps_batches');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableTrazas (
          traza_client_id TEXT PRIMARY KEY,
          remote_id       INTEGER,
          operador_id     INTEGER NOT NULL,
          name            TEXT    NOT NULL,
          started_at      TEXT    NOT NULL,
          ended_at        TEXT,
          updated_at      TEXT    NOT NULL,
          synced_at       TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tablePuntos (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          traza_client_id TEXT    NOT NULL,
          captured_at     TEXT    NOT NULL,
          lat             REAL    NOT NULL,
          lng             REAL    NOT NULL,
          accuracy_m      REAL,
          altitude_m      REAL,
          speed_mps       REAL,
          FOREIGN KEY (traza_client_id) REFERENCES $_tableTrazas(traza_client_id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${_tablePuntos}_traza '
        'ON $_tablePuntos(traza_client_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${_tablePuntos}_time '
        'ON $_tablePuntos(captured_at)',
      );
    }
  }

  // ─────────────────────────── LocalStore contract ───────────────────────

  @override
  Future<void> upsert(TrazaEntity entity, {DatabaseExecutor? txn}) async {
    final executor = txn ?? _db;
    if (executor is Database) {
      await executor.transaction((tx) => _upsertWith(tx, entity));
      return;
    }
    await _upsertWith(executor, entity);
  }

  Future<void> _upsertWith(
    DatabaseExecutor executor,
    TrazaEntity entity,
  ) async {
    await executor.insert(
      _tableTrazas,
      {
        'traza_client_id': entity.clientId,
        'remote_id': entity.id,
        'operador_id': entity.operadorId,
        'name': entity.name,
        'started_at': entity.startedAt.toIso8601String(),
        'ended_at': entity.endedAt?.toIso8601String(),
        'updated_at': entity.updatedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Replace points wholesale so re-saving the same traza is idempotent.
    // NEVER call this while a traza is actively recording — use
    // [appendPoints] instead, it is the only append-only path.
    await executor.delete(
      _tablePuntos,
      where: 'traza_client_id = ?',
      whereArgs: [entity.clientId],
    );
    final batch = executor.batch();
    for (final p in entity.points) {
      batch.insert(_tablePuntos, _pointRow(entity.clientId, p));
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> delete(String clientId, {DatabaseExecutor? txn}) async {
    final executor = txn ?? _db;
    await executor.delete(
      _tableTrazas,
      where: 'traza_client_id = ?',
      whereArgs: [clientId],
    );
    // Cascade is on but cover non-FK databases too.
    await executor.delete(
      _tablePuntos,
      where: 'traza_client_id = ?',
      whereArgs: [clientId],
    );
  }

  /// Push-only store — trazas are never pulled from the backend, so there is
  /// no remote-id lookup path. Always returns `null`.
  @override
  Future<TrazaEntity?> findByRemoteId(String remoteId) async => null;

  @override
  Future<TrazaEntity?> findByClientId(String clientId) async {
    final rows = await _db.query(
      _tableTrazas,
      where: 'traza_client_id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final pointsRows = await _db.query(
      _tablePuntos,
      where: 'traza_client_id = ?',
      whereArgs: [clientId],
      orderBy: 'captured_at ASC',
    );
    return _toEntity(rows.first, pointsRows);
  }

  @override
  Future<List<TrazaEntity>> findWhere(String column, Object? value) async {
    final rows = await _db.query(
      _tableTrazas,
      where: '$column = ?',
      whereArgs: [value],
      orderBy: 'started_at DESC',
    );
    if (rows.isEmpty) return const [];
    return _groupWithPoints(rows);
  }

  /// 2 queries instead of N+1: one for all traza headers, one for all
  /// points, grouped in memory by `traza_client_id`.
  @override
  Future<List<TrazaEntity>> findAll() async {
    final rows = await _db.query(_tableTrazas, orderBy: 'started_at DESC');
    if (rows.isEmpty) return const [];
    return _groupWithPoints(rows);
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
      _tableTrazas,
      updates,
      where: 'traza_client_id = ?',
      whereArgs: [clientId],
    );
  }

  // ───────────────────────── Recording-specific API ───────────────────────

  /// Appends [pts] to [trazaClientId] with a batch INSERT — never touches
  /// existing rows. This is the hot path called every ~30 s while recording;
  /// unlike [upsert] it never rewrites/duplicates already-persisted points.
  Future<void> appendPoints(String trazaClientId, List<TrazaPunto> pts) async {
    if (pts.isEmpty) return;
    final batch = _db.batch();
    for (final p in pts) {
      batch.insert(_tablePuntos, _pointRow(trazaClientId, p));
    }
    await batch.commit(noResult: true);
  }

  /// The open traza (`ended_at IS NULL`) for [operadorId], if any. There can
  /// be at most one per operator.
  Future<TrazaEntity?> findOpen(int operadorId) async {
    final rows = await _db.query(
      _tableTrazas,
      where: 'operador_id = ? AND ended_at IS NULL',
      whereArgs: [operadorId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final pointsRows = await _db.query(
      _tablePuntos,
      where: 'traza_client_id = ?',
      whereArgs: [rows.first['traza_client_id']],
      orderBy: 'captured_at ASC',
    );
    return _toEntity(rows.first, pointsRows);
  }

  /// Any open traza regardless of operator — used by the crash-recovery flow
  /// which may run before the current operador is known to match.
  Future<TrazaEntity?> findAnyOpen() async {
    final rows = await _db.query(
      _tableTrazas,
      where: 'ended_at IS NULL',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final pointsRows = await _db.query(
      _tablePuntos,
      where: 'traza_client_id = ?',
      whereArgs: [rows.first['traza_client_id']],
      orderBy: 'captured_at ASC',
    );
    return _toEntity(rows.first, pointsRows);
  }

  /// Closes [trazaClientId]: sets its final [name] and [endedAt]. Does not
  /// touch the points table.
  Future<void> finalize({
    required String trazaClientId,
    required String name,
    required DateTime endedAt,
  }) async {
    await _db.update(
      _tableTrazas,
      {
        'name': name,
        'ended_at': endedAt.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'traza_client_id = ?',
      whereArgs: [trazaClientId],
    );
  }

  /// Deletes trazas (and, via cascade, their points) whose `synced_at` is
  /// not null. Returns the number of traza rows removed.
  Future<int> deleteSynced() async {
    return _db.transaction((tx) async {
      final rows = await tx.query(
        _tableTrazas,
        columns: const ['traza_client_id'],
        where: 'synced_at IS NOT NULL',
      );
      if (rows.isEmpty) return 0;
      final clientIds =
          rows.map((r) => r['traza_client_id']! as String).toList();
      final placeholders = List.filled(clientIds.length, '?').join(',');
      // FK cascade is not guaranteed enabled on every sqflite connection
      // (e.g. `PRAGMA foreign_keys` is off by default) — delete points
      // explicitly, same defensive approach as [delete].
      await tx.delete(
        _tablePuntos,
        where: 'traza_client_id IN ($placeholders)',
        whereArgs: clientIds,
      );
      return tx.delete(
        _tableTrazas,
        where: 'traza_client_id IN ($placeholders)',
        whereArgs: clientIds,
      );
    });
  }

  // ─────────────────────────────── Internals ──────────────────────────────

  Map<String, Object?> _pointRow(String trazaClientId, TrazaPunto p) => {
        'traza_client_id': trazaClientId,
        'captured_at': p.capturedAt.toIso8601String(),
        'lat': p.lat,
        'lng': p.lng,
        'accuracy_m': p.accuracyMeters,
        'altitude_m': p.altitudeMeters,
        'speed_mps': p.speedMps,
      };

  Future<List<TrazaEntity>> _groupWithPoints(
    List<Map<String, Object?>> rows,
  ) async {
    final clientIds = rows.map((r) => r['traza_client_id']! as String).toList();
    final placeholders = List.filled(clientIds.length, '?').join(',');
    final allPointRows = await _db.query(
      _tablePuntos,
      where: 'traza_client_id IN ($placeholders)',
      whereArgs: clientIds,
      orderBy: 'captured_at ASC',
    );

    final pointsByTraza = <String, List<Map<String, Object?>>>{};
    for (final row in allPointRows) {
      final key = row['traza_client_id']! as String;
      (pointsByTraza[key] ??= []).add(row);
    }

    return rows.map((row) {
      final clientId = row['traza_client_id']! as String;
      return _toEntity(row, pointsByTraza[clientId] ?? const []);
    }).toList();
  }

  TrazaEntity _toEntity(
    Map<String, Object?> row,
    List<Map<String, Object?>> pointsRows,
  ) {
    final startedAt = DateTime.parse(row['started_at']! as String);
    final rawEndedAt = row['ended_at'] as String?;
    final endedAt = rawEndedAt == null ? null : DateTime.parse(rawEndedAt);

    // Deterministic fallback if updated_at doesn't parse: never DateTime.now().
    final rawUpdatedAt = row['updated_at'];
    DateTime? updatedAt;
    if (rawUpdatedAt != null) {
      updatedAt = DateTime.tryParse(rawUpdatedAt as String);
      if (updatedAt == null) {
        if (kDebugMode) {
          AppLog.w(
            'TrazaLocalStore: unparseable updated_at="$rawUpdatedAt" '
            'for traza ${row['traza_client_id']}; falling back to '
            '${endedAt ?? startedAt}.',
          );
        }
        updatedAt = endedAt ?? startedAt; // deterministic fallback
      }
    }

    return TrazaEntity(
      clientId: row['traza_client_id']! as String,
      id: row['remote_id'] as int?,
      operadorId: (row['operador_id'] as int?) ?? 0,
      name: row['name'] as String?,
      startedAt: startedAt,
      endedAt: endedAt,
      updatedAt: updatedAt,
      points: pointsRows
          .map((r) => TrazaPunto(
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
