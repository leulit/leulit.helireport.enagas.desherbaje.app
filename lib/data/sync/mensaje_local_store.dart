import 'package:sqflite/sqflite.dart';

import '../../core/sync/contracts/local_store.dart';
import '../model/mensaje_entity.dart';

class MensajeLocalStore implements LocalStore<MensajeSegmentoEntity> {
  static const String _table = 'mensajes_segmento';

  final Database _db;

  MensajeLocalStore(this._db);

  @override
  String get entityType => 'mensaje';

  @override
  int get schemaVersion => 1;

  @override
  Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    if (from == 0 && to == 1) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_table (
          client_id    TEXT PRIMARY KEY,
          id           INTEGER,
          segmento_id  INTEGER NOT NULL,
          mensaje      TEXT    NOT NULL,
          enviado_por  INTEGER,
          created_at   TEXT    NOT NULL,
          updated_at   TEXT    NOT NULL,
          synced_at    TEXT
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${_table}_seg '
        'ON $_table(segmento_id)',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_${_table}_remote '
        'ON $_table(id) WHERE id IS NOT NULL',
      );
    }
  }

  @override
  Future<void> upsert(MensajeSegmentoEntity entity, {DatabaseExecutor? txn}) async {
    final executor = txn ?? _db;
    await executor.insert(
      _table,
      _entityToRow(entity),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
  Future<MensajeSegmentoEntity?> findByClientId(String clientId) async {
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
  Future<List<MensajeSegmentoEntity>> findAll() async {
    final rows = await _db.query(_table, orderBy: 'created_at DESC');
    return rows.map(_rowToEntity).toList(growable: false);
  }

  @override
  Future<List<MensajeSegmentoEntity>> findWhere(
    String column,
    Object? value,
  ) async {
    final rows = await _db.query(
      _table,
      where: '$column = ?',
      whereArgs: [value],
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToEntity).toList(growable: false);
  }

  /// Push-only store — mensajes are never pulled individually, so there is
  /// no remote-id lookup path. Always returns `null`.
  @override
  Future<MensajeSegmentoEntity?> findByRemoteId(String remoteId) async => null;

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
      if (asInt != null) updates['id'] = asInt;
    }
    await executor.update(
      _table,
      updates,
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  /// Returns local mensajes for a given segmento (used as a fallback when
  /// the network call to fetch fresh data fails offline).
  Future<List<MensajeSegmentoEntity>> findBySegmento(int segmentoId) =>
      findWhere('segmento_id', segmentoId);

  Map<String, Object?> _entityToRow(MensajeSegmentoEntity e) => {
        'client_id': e.clientId,
        'id': e.id,
        'segmento_id': e.segmentoId,
        'mensaje': e.mensaje,
        'enviado_por': e.enviadoPor,
        'created_at': e.createdAt.toIso8601String(),
        'updated_at': e.updatedAt.toIso8601String(),
      };

  MensajeSegmentoEntity _rowToEntity(Map<String, Object?> row) {
    return MensajeSegmentoEntity(
      clientId: row['client_id'] as String,
      id: row['id'] as int?,
      segmentoId: (row['segmento_id'] as int?) ?? 0,
      mensaje: (row['mensaje'] as String?) ?? '',
      enviadoPor: row['enviado_por'] as int?,
      createdAt: DateTime.tryParse((row['created_at'] as String?) ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse((row['updated_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}
