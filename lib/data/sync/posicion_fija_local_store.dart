import 'package:sqflite/sqflite.dart';

import '../../core/app_log.dart';
import '../../core/sync/contracts/local_store.dart';
import '../../domain/entities/posicion_fija_entity.dart';

/// SQLite-backed [LocalStore] for [PosicionFijaEntity]. Owns the
/// `posiciones_fijas` table schema (PK = `client_id` UUID). Entidad
/// pull-only: no hay outbox asociado, solo lectura local tras un pull.
class PosicionFijaLocalStore implements LocalStore<PosicionFijaEntity> {
  static const String _table = 'posiciones_fijas';

  final Database _db;

  PosicionFijaLocalStore(this._db);

  @override
  String get entityType => 'posicion_fija';

  @override
  int get schemaVersion => 1;

  @override
  Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    if (from == 0 && to == 1) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_table (
          client_id         TEXT PRIMARY KEY,
          id                INTEGER,
          title             TEXT NOT NULL,
          latitud           REAL,
          longitud          REAL,
          fixed_latitude    REAL,
          fixed_longitude   REAL,
          ctname            TEXT NOT NULL,
          zona              TEXT,
          tramo             TEXT,
          subtramo          TEXT,
          tipo_punto        TEXT,
          tipovigilancia    TEXT,
          trazaname         TEXT,
          fotos             TEXT,
          fecha             TEXT,
          updated_at        TEXT NOT NULL,
          synced_at         TEXT
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${_table}_ctname ON $_table(ctname)',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_${_table}_remote '
        'ON $_table(id) WHERE id IS NOT NULL',
      );
    }
  }

  @override
  Future<void> upsert(PosicionFijaEntity entity, {DatabaseExecutor? txn}) async {
    final executor = txn ?? _db;
    // Two-step reconciliation: UPDATE first (preserves synced_at because
    // _entityToRow omits it), then INSERT only for genuinely new rows. A
    // conflict on idx_posiciones_fijas_remote (same remote id, different
    // client_id) throws with ConflictAlgorithm.abort instead of silently
    // destroying the existing local row — surfaces data collisions instead
    // of hiding them (same pattern as SegmentoLocalStore).
    final changed = await executor.update(
      _table,
      _entityToRow(entity),
      where: 'client_id = ?',
      whereArgs: [entity.clientId],
    );
    if (changed == 0) {
      await executor.insert(
        _table,
        _entityToRow(entity),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  @override
  Future<void> delete(String clientId, {DatabaseExecutor? txn}) async {
    final executor = txn ?? _db;
    await executor.delete(
      _table,
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  @override
  Future<PosicionFijaEntity?> findByClientId(String clientId) async {
    final rows = await _db.query(
      _table,
      where: 'client_id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToEntity(rows.first);
  }

  @override
  Future<List<PosicionFijaEntity>> findAll() async {
    final rows = await _db.query(_table, orderBy: 'title ASC');
    return rows.map(_rowToEntity).toList(growable: false);
  }

  @override
  Future<List<PosicionFijaEntity>> findWhere(
    String column,
    Object? value,
  ) async {
    final rows = await _db.query(
      _table,
      where: '$column = ?',
      whereArgs: [value],
      orderBy: 'title ASC',
    );
    return rows.map(_rowToEntity).toList(growable: false);
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
      if (asInt != null) {
        updates['id'] = asInt;
      } else {
        // A5: column `id` is INTEGER; non-numeric remoteId cannot be stored.
        // Log the discard so it is observable in release builds.
        AppLog.w(
          'PosicionFijaLocalStore.markSynced: remoteId "$remoteId" is not a '
          'valid integer — id column left unchanged for clientId=$clientId.',
        );
      }
    }
    await executor.update(
      _table,
      updates,
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  /// Looks up a posición fija by its backend-assigned numeric id.
  ///
  /// [remoteId] is the string representation of the backend id (e.g. `"42"`).
  /// Returns `null` when [remoteId] cannot be parsed as an integer — the
  /// discard is logged so it is observable in release builds (A5).
  @override
  Future<PosicionFijaEntity?> findByRemoteId(String remoteId) async {
    final asInt = int.tryParse(remoteId);
    if (asInt == null) {
      AppLog.w(
        'PosicionFijaLocalStore.findByRemoteId: "$remoteId" is not a valid '
        'integer — returning null.',
      );
      return null;
    }
    final rows = await _db.query(
      _table,
      where: 'id = ?',
      whereArgs: [asInt],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToEntity(rows.first);
  }

  /// Returns posiciones fijas belonging to any of the given CT names.
  Future<List<PosicionFijaEntity>> findByCtNames(List<String> ctNames) async {
    if (ctNames.isEmpty) return const [];
    final placeholders = List.filled(ctNames.length, '?').join(',');
    final rows = await _db.query(
      _table,
      where: 'ctname IN ($placeholders)',
      whereArgs: ctNames,
      orderBy: 'title ASC',
    );
    return rows.map(_rowToEntity).toList(growable: false);
  }

  Map<String, Object?> _entityToRow(PosicionFijaEntity e) => {
        'client_id': e.clientId,
        'id': e.id,
        'title': e.title,
        'latitud': e.latitud,
        'longitud': e.longitud,
        'fixed_latitude': e.fixedLatitude,
        'fixed_longitude': e.fixedLongitude,
        'ctname': e.ctname,
        'zona': e.zona,
        'tramo': e.tramo,
        'subtramo': e.subtramo,
        'tipo_punto': e.tipoPunto,
        'tipovigilancia': e.tipoVigilancia,
        'trazaname': e.trazaname,
        'fotos': e.fotos,
        'fecha': e.fecha?.toIso8601String(),
        'updated_at': e.updatedAt.toIso8601String(),
      };

  PosicionFijaEntity _rowToEntity(Map<String, Object?> row) {
    final fechaRaw = row['fecha'] as String?;
    final updatedAtRaw = row['updated_at'] as String;

    return PosicionFijaEntity(
      id: row['id'] as int?,
      clientId: row['client_id'] as String,
      title: (row['title'] as String?) ?? '',
      ctname: (row['ctname'] as String?) ?? '',
      latitud: (row['latitud'] as num?)?.toDouble(),
      longitud: (row['longitud'] as num?)?.toDouble(),
      fixedLatitude: (row['fixed_latitude'] as num?)?.toDouble(),
      fixedLongitude: (row['fixed_longitude'] as num?)?.toDouble(),
      zona: row['zona'] as String?,
      tramo: row['tramo'] as String?,
      subtramo: row['subtramo'] as String?,
      tipoPunto: row['tipo_punto'] as String?,
      tipoVigilancia: row['tipovigilancia'] as String?,
      trazaname: row['trazaname'] as String?,
      fotos: row['fotos'] as String?,
      fecha: fechaRaw != null ? DateTime.tryParse(fechaRaw) : null,
      updatedAt:
          DateTime.tryParse(updatedAtRaw) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
