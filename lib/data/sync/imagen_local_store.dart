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
  int get schemaVersion => 3;

  @override
  Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    if (from < 1 && to >= 1) {
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
    if (from < 2 && to >= 2) {
      await db.execute(
        'ALTER TABLE $_table ADD COLUMN segmento_client_id TEXT',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${_table}_segclient '
        'ON $_table(segmento_client_id)',
      );
    }
    if (from < 3 && to >= 3) {
      // Drop latitud/longitud/fixed_latitud/fixed_longitud y añade gis_json.
      // SQLite DROP COLUMN no es fiable en Android viejo → table-rebuild.
      await db.execute('''
        CREATE TABLE ${_table}_new (
          client_id          TEXT PRIMARY KEY,
          id                 INTEGER,
          actividad_id       INTEGER NOT NULL DEFAULT 0,
          segmento_id        INTEGER NOT NULL,
          tipo_foto          TEXT NOT NULL,
          filename           TEXT NOT NULL,
          ruta               TEXT NOT NULL,
          url                TEXT,
          mime_type          TEXT NOT NULL DEFAULT 'image/jpeg',
          tamanyo_bytes      INTEGER,
          capturada_at       TEXT NOT NULL,
          subida_at          TEXT,
          subida_por         INTEGER,
          created_at         TEXT,
          updated_at         TEXT,
          synced_at          TEXT,
          needs_sync         INTEGER NOT NULL DEFAULT 1,
          segmento_client_id TEXT,
          gis_json           TEXT
        )
      ''');
      await db.execute('''
        INSERT INTO ${_table}_new (
          client_id, id, actividad_id, segmento_id, tipo_foto, filename,
          ruta, url, mime_type, tamanyo_bytes, capturada_at, subida_at,
          subida_por, created_at, updated_at, synced_at, needs_sync,
          segmento_client_id
        )
        SELECT
          client_id, id, actividad_id, segmento_id, tipo_foto, filename,
          ruta, url, mime_type, tamanyo_bytes, capturada_at, subida_at,
          subida_por, created_at, updated_at, synced_at, needs_sync,
          segmento_client_id
        FROM $_table
      ''');
      await db.execute('DROP TABLE $_table');
      await db.execute('ALTER TABLE ${_table}_new RENAME TO $_table');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${_table}_seg '
        'ON $_table(segmento_id)',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_${_table}_remote '
        'ON $_table(id) WHERE id IS NOT NULL',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${_table}_segclient '
        'ON $_table(segmento_client_id)',
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

  @override
  Future<List<ImagenSegmentoEntity>> findWhere(
    String column,
    Object? value,
  ) async {
    final rows = await _db.query(
      _table,
      where: '$column = ?',
      whereArgs: [value],
      orderBy: 'capturada_at DESC',
    );
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

  /// Estampa el id remoto del segmento en todas las imágenes hijas
  /// enlazadas por `segmento_client_id`. Se usa cuando un segmento nuevo
  /// obtiene su id de backend, para que sus imágenes suban ya vinculadas.
  Future<void> setSegmentoRemoteId(
    String segmentoClientId,
    int backendId, {
    DatabaseExecutor? txn,
  }) async {
    await (txn ?? _db).update(
      _table,
      {'segmento_id': backendId},
      where: 'segmento_client_id = ?',
      whereArgs: [segmentoClientId],
    );
  }
}
