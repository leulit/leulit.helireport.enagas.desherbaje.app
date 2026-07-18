import 'package:sqflite/sqflite.dart';

import '../../core/sync/contracts/local_store.dart';
import '../../domain/entities/video_segmento_entity.dart';

/// SQLite-backed [LocalStore] for [VideoSegmentoEntity].
///
/// Persists in `videos_segmento`. The entity's `clientId` is a UUID generated
/// at construction time and stored in the `client_id` column, so the outbox is
/// idempotent before the backend assigns a remote `id`.
///
/// La columna `upload_offset` almacena el último byte confirmado por el backend
/// en la subida chunked resumable. El adapter la actualiza con
/// [saveUploadOffset] tras cada chunk exitoso.
class VideoLocalStore implements LocalStore<VideoSegmentoEntity> {
  static const String _table = 'videos_segmento';

  final Database _db;

  VideoLocalStore(this._db);

  @override
  String get entityType => 'video';

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
          tipo_video       TEXT NOT NULL,
          filename         TEXT NOT NULL,
          ruta             TEXT NOT NULL,
          url              TEXT,
          mime_type        TEXT NOT NULL DEFAULT 'video/mp4',
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
          needs_sync       INTEGER NOT NULL DEFAULT 1,
          upload_offset    INTEGER NOT NULL DEFAULT 0,
          upload_id        TEXT
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
          tipo_video         TEXT NOT NULL,
          filename           TEXT NOT NULL,
          ruta               TEXT NOT NULL,
          url                TEXT,
          mime_type          TEXT NOT NULL DEFAULT 'video/mp4',
          tamanyo_bytes      INTEGER,
          capturada_at       TEXT NOT NULL,
          subida_at          TEXT,
          subida_por         INTEGER,
          created_at         TEXT,
          updated_at         TEXT,
          synced_at          TEXT,
          needs_sync         INTEGER NOT NULL DEFAULT 1,
          upload_offset      INTEGER NOT NULL DEFAULT 0,
          upload_id          TEXT,
          segmento_client_id TEXT,
          gis_json           TEXT
        )
      ''');
      await db.execute('''
        INSERT INTO ${_table}_new (
          client_id, id, actividad_id, segmento_id, tipo_video, filename,
          ruta, url, mime_type, tamanyo_bytes, capturada_at, subida_at,
          subida_por, created_at, updated_at, synced_at, needs_sync,
          upload_offset, upload_id, segmento_client_id
        )
        SELECT
          client_id, id, actividad_id, segmento_id, tipo_video, filename,
          ruta, url, mime_type, tamanyo_bytes, capturada_at, subida_at,
          subida_por, created_at, updated_at, synced_at, needs_sync,
          upload_offset, upload_id, segmento_client_id
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
    VideoSegmentoEntity entity, {
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
  Future<VideoSegmentoEntity?> findByClientId(String clientId) async {
    final rows = await _db.query(
      _table,
      where: 'client_id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return VideoSegmentoEntity.fromMap(rows.first);
  }

  @override
  Future<List<VideoSegmentoEntity>> findAll() async {
    final rows = await _db.query(_table, orderBy: 'capturada_at DESC');
    return rows.map(VideoSegmentoEntity.fromMap).toList(growable: false);
  }

  @override
  Future<List<VideoSegmentoEntity>> findWhere(
    String column,
    Object? value,
  ) async {
    final rows = await _db.query(
      _table,
      where: '$column = ?',
      whereArgs: [value],
      orderBy: 'capturada_at DESC',
    );
    return rows.map(VideoSegmentoEntity.fromMap).toList(growable: false);
  }

  /// Push-only store — videos are never pulled from the backend, so there is
  /// no remote-id lookup path. Always returns `null`.
  @override
  Future<VideoSegmentoEntity?> findByRemoteId(String remoteId) async => null;

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
      if (parsed != null) {
        values['id'] = parsed;
      } else {
        // Non-integer remoteId → store as upload_id (UUID from video session).
        values['upload_id'] = remoteId;
      }
    }
    await executor.update(
      _table,
      values,
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  /// Estampa el id remoto del segmento en todos los vídeos hijos enlazados
  /// por `segmento_client_id`. Se usa cuando un segmento nuevo obtiene su id
  /// de backend, para que sus vídeos suban ya vinculados.
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

  /// Persists the server-assigned [uploadId] for the upload session of the
  /// video identified by [clientId]. Called immediately after a successful
  /// `initVideoUpload` so the session can be resumed across app restarts.
  Future<void> saveUploadId(String clientId, String uploadId) async {
    await _db.update(
      _table,
      {'upload_id': uploadId},
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  /// Persists the [offset] confirmed by the server for the chunked upload
  /// of the video identified by [clientId]. Called after each successful chunk
  /// so a subsequent session can resume without re-sending confirmed bytes.
  Future<void> saveUploadOffset(String clientId, int offset) async {
    await _db.update(
      _table,
      {'upload_offset': offset},
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  /// Descarta la sesión de subida (`upload_id` + `upload_offset`) de TODOS los
  /// vídeos del segmento [segmentoClientId].
  ///
  /// Una sesión de subida pertenece a UN intento de envío del sobre. Al
  /// entregarse un `upsert` nuevo, el backend anula el intento anterior y borra
  /// sus filas y ficheros `pending` (§2 regla 2): la sesión guardada apunta a
  /// bytes que ya no existen en el servidor. Si no se descarta, el adapter
  /// reanudaría contra ella, leería `complete: true` y reportaría éxito sin
  /// subir nada — y el `sync-complete` posterior purgaría el vídeo local, que
  /// desaparecería de todas partes. Limpia la sesión y el adapter hace `init`
  /// nuevo y resube los bytes.
  Future<void> clearUploadSessions(
    String segmentoClientId, {
    DatabaseExecutor? txn,
  }) async {
    await (txn ?? _db).update(
      _table,
      {'upload_id': null, 'upload_offset': 0},
      where: 'segmento_client_id = ?',
      whereArgs: [segmentoClientId],
    );
  }
}
