import 'package:sqflite/sqflite.dart';

import '../../core/sync/contracts/local_store.dart';
import '../../domain/entities/imagen_segmento_entity.dart';

/// SQLite-backed [LocalStore] for [ImagenSegmentoEntity].
///
/// Persists in `imagenes_segmento`. The entity's `clientId` is a UUID
/// generated at construction time and stored in the `client_id` column, so
/// the outbox is idempotent before the backend assigns a remote `id`.
class ImagenLocalStore implements LocalStore<ImagenSegmentoEntity> {
  static const String _table = 'imagenes_segmento';

  final Database _db;

  ImagenLocalStore(this._db);

  @override
  String get entityType => 'imagen';

  @override
  int get schemaVersion => 1;

  @override
  Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    if (from == 0 && to == 1) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_table (
          client_id        TEXT PRIMARY KEY,
          id               INTEGER,
          actividad_id     INTEGER NOT NULL DEFAULT 0,
          segmento_id      INTEGER NOT NULL,
          tipo_foto        TEXT NOT NULL,
          filename         TEXT NOT NULL,
          ruta             TEXT NOT NULL,
          url              TEXT,
          mime_type        TEXT NOT NULL DEFAULT 'image/jpeg',
          tamanyo_bytes    INTEGER,
          latitud          REAL,
          longitud         REAL,
          fixed_latitud    REAL,
          fixed_longitud   REAL,
          capturada_at     TEXT NOT NULL,
          subida_at        TEXT,
          subida_por       INTEGER,
          created_at       TEXT,
          updated_at       TEXT,
          synced_at        TEXT,
          needs_sync       INTEGER NOT NULL DEFAULT 1
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
  Future<void> upsert(
    ImagenSegmentoEntity entity, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? _db;
    await executor.insert(
      _table,
      entity.toMap(),
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
  Future<ImagenSegmentoEntity?> findByClientId(String clientId) async {
    final rows = await _db.query(
      _table,
      where: 'client_id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ImagenSegmentoEntity.fromMap(rows.first);
  }

  @override
  Future<List<ImagenSegmentoEntity>> findAll() async {
    final rows = await _db.query(_table, orderBy: 'capturada_at DESC');
    return rows.map(ImagenSegmentoEntity.fromMap).toList(growable: false);
  }

  /// Push-only store — images are never pulled from the backend, so there is
  /// no remote-id lookup path. Always returns `null`.
  @override
  Future<ImagenSegmentoEntity?> findByRemoteId(String remoteId) async => null;

  @override
  Future<void> markSynced({
    required String clientId,
    String? remoteId,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? _db;
    final values = <String, Object?>{
      'synced_at': DateTime.now().toIso8601String(),
      'needs_sync': 0,
    };
    if (remoteId != null) {
      final parsed = int.tryParse(remoteId);
      if (parsed != null) values['id'] = parsed;
    }
    await executor.update(
      _table,
      values,
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }
}
