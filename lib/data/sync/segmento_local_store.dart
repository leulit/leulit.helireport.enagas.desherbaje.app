import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/app_log.dart';
import '../../core/sync/contracts/local_store.dart';
import '../../domain/entities/imagen_segmento_entity.dart';
import '../../domain/entities/segmento_entity.dart';
import '../model/mensaje_entity.dart';

/// SQLite-backed [LocalStore] for [SegmentoEntity]. Owns the `segmentos`
/// table schema (PK = `client_id` UUID).
class SegmentoLocalStore implements LocalStore<SegmentoEntity> {
  static const String _table = 'segmentos';

  final Database _db;

  SegmentoLocalStore(this._db);

  @override
  String get entityType => 'segmento';

  @override
  int get schemaVersion => 3;

  @override
  Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    // v1 (columna `ct_id INTEGER`) → v2 (columna `ctname TEXT`): el segmento
    // identifica su CT por NOMBRE, no por id (contrato §3/§8: la descarga
    // `GET /segmentos/contratista` filtra por nombre de CT). App pre-release,
    // sin datos de producción que preservar y sin poder mapear el id al nombre
    // en SQLite → DROP + CREATE en vez de reconstruir la tabla.
    if (from == 1 && to >= 2) {
      await db.execute('DROP TABLE IF EXISTS $_table');
    }
    if (from < 2 && to >= 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_table (
          client_id         TEXT PRIMARY KEY,
          id                INTEGER,
          ctname            TEXT NOT NULL DEFAULT '',
          nombre            TEXT,
          descripcion       TEXT NOT NULL DEFAULT '',
          traza             TEXT,
          tipo_instalacion  TEXT NOT NULL DEFAULT 'lineal',
          pk_inicio         REAL,
          pk_fin            REAL,
          lat_inicio        REAL,
          lng_inicio        REAL,
          lat_fin           REAL,
          lng_fin           REAL,
          ubicacion_gis     TEXT,
          tipo_actividad    TEXT NOT NULL DEFAULT 'deshierbe_selectivo',
          estado            TEXT NOT NULL DEFAULT 'propuesta',
          imagenes_json     TEXT,
          mensajes_json     TEXT,
          created_at        TEXT,
          fecha_inicio      TEXT,
          fecha_fin         TEXT,
          updated_at        TEXT NOT NULL,
          synced_at         TEXT,
          sync_confirmed_at INTEGER
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
    // v2 → v3: `sync_confirmed_at` (epoch ms del último `sync-complete` 200).
    // Solo se ALTERa viniendo EXACTAMENTE de v2: en una instalación limpia
    // (from == 0) el CREATE de arriba ya trae la columna, y un ALTER encima
    // moriría con `duplicate column name`.
    if (from == 2 && to >= 3) {
      await db.execute(
        'ALTER TABLE $_table ADD COLUMN sync_confirmed_at INTEGER',
      );
    }
  }

  /// Instante (epoch ms) del último `sync-complete` confirmado con 200 para
  /// este segmento, o `null` si nunca se cerró.
  ///
  /// Es la frontera que separa lo que el backend tiene como `complete` de lo
  /// que tiene como `pending`: un job del sobre con `synced_at` posterior a
  /// esta marca subió en un intento que nadie cerró, así que el próximo
  /// `upsert` lo borrará (`cleanupPendingChildren`) y hay que reenviarlo.
  Future<int?> readSyncConfirmedAt(String clientId) async {
    final rows = await _db.query(
      _table,
      columns: ['sync_confirmed_at'],
      where: 'client_id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['sync_confirmed_at'] as int?;
  }

  /// Graba la frontera de cierre. [atMs] debe ser el `max(synced_at)` de los
  /// jobs del sobre, NO `DateTime.now()`: ambos valores salen entonces de la
  /// misma fuente (`OutboxQueue.markSynced`) y un salto del reloj del
  /// dispositivo no puede dejar jobs ya cerrados al otro lado de la frontera.
  Future<void> markSyncConfirmed(String clientId, int atMs) async {
    await _db.update(
      _table,
      {'sync_confirmed_at': atMs},
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  @override
  Future<void> upsert(SegmentoEntity entity, {DatabaseExecutor? txn}) async {
    final executor = txn ?? _db;
    // Two-step reconciliation: UPDATE first (preserves synced_at because
    // _entityToRow omits it), then INSERT only for genuinely new rows.
    // A conflict on idx_segmentos_remote (same remote id, different client_id)
    // throws with ConflictAlgorithm.abort instead of silently destroying the
    // existing local row — surfaces data collisions instead of hiding them.
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

  /// Refresca solo el snapshot embebido (`imagenes_json`/`mensajes_json`) de
  /// la fila, sin tocar el resto de columnas — ni siquiera `synced_at`/
  /// `sync_confirmed_at`, que tienen sus propios setters.
  ///
  /// Usado por [PurgeSyncedSegmentoUseCase] para fundir en el snapshot los
  /// hijos locales que ya están confirmados en nube justo ANTES de borrar sus
  /// filas: así Antes/Después y Mensajes siguen viéndolos aunque la fila hija
  /// ya no exista, sin esperar al siguiente pull manual.
  Future<void> updateEmbeddedMedia(
    String clientId, {
    required List<ImagenSegmentoEntity> imagenes,
    required List<MensajeSegmentoEntity> mensajes,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? _db;
    await executor.update(
      _table,
      {
        'imagenes_json': jsonEncode(imagenes.map((i) => i.toJson()).toList()),
        'mensajes_json': jsonEncode(mensajes.map((m) => m.toJson()).toList()),
      },
      where: 'client_id = ?',
      whereArgs: [clientId],
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
  Future<SegmentoEntity?> findByClientId(String clientId) async {
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
  Future<List<SegmentoEntity>> findAll() async {
    final rows = await _db.query(_table, orderBy: 'fecha_fin DESC');
    return rows.map(_rowToEntity).toList(growable: false);
  }

  @override
  Future<List<SegmentoEntity>> findWhere(String column, Object? value) async {
    final rows = await _db.query(
      _table,
      where: '$column = ?',
      whereArgs: [value],
      orderBy: 'fecha_fin DESC',
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
          'SegmentoLocalStore.markSynced: remoteId "$remoteId" is not a valid '
          'integer — id column left unchanged for clientId=$clientId.',
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

  /// Looks up a segmento by its backend-assigned numeric id.
  ///
  /// [remoteId] is the string representation of the backend id (e.g. `"42"`).
  /// Returns `null` when [remoteId] cannot be parsed as an integer — the
  /// discard is logged so it is observable in release builds (A5).
  @override
  Future<SegmentoEntity?> findByRemoteId(String remoteId) async {
    final asInt = int.tryParse(remoteId);
    if (asInt == null) {
      AppLog.w(
        'SegmentoLocalStore.findByRemoteId: "$remoteId" is not a valid '
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

  /// Returns segmentos belonging to any of the given CT names.
  Future<List<SegmentoEntity>> findByCtNames(List<String> ctNames) async {
    if (ctNames.isEmpty) return const [];
    final placeholders = List.filled(ctNames.length, '?').join(',');
    final rows = await _db.query(
      _table,
      where: 'ctname IN ($placeholders)',
      whereArgs: ctNames,
      orderBy: 'fecha_fin DESC',
    );
    return rows.map(_rowToEntity).toList(growable: false);
  }

  Map<String, Object?> _entityToRow(SegmentoEntity e) => {
        'client_id': e.clientId,
        'id': e.id,
        'ctname': e.ctname,
        'nombre': e.nombre,
        'descripcion': e.descripcion,
        'traza': e.traza,
        'tipo_instalacion': e.tipoInstalacion.asString,
        'pk_inicio': e.pkInicio,
        'pk_fin': e.pkFin,
        'lat_inicio': e.latInicio,
        'lng_inicio': e.lngInicio,
        'lat_fin': e.latFin,
        'lng_fin': e.lngFin,
        'ubicacion_gis': jsonEncode(e.ubicacionGisAsGeoJSON),
        'tipo_actividad': e.tipoActividad.descripcion,
        'estado': e.estado.descripcion,
        'imagenes_json': jsonEncode(e.imagenes.map((i) => i.toJson()).toList()),
        'mensajes_json': jsonEncode(e.mensajes.map((m) => m.toJson()).toList()),
        'created_at': e.createdAt?.toIso8601String(),
        'fecha_inicio': e.fechaInicio?.toIso8601String(),
        'fecha_fin': e.fechaFin?.toIso8601String(),
        'updated_at': e.updatedAt.toIso8601String(),
      };

  SegmentoEntity _rowToEntity(Map<String, Object?> row) {
    final ubicacion = _parseUbicacion(row['ubicacion_gis'] as String?);

    final entity = SegmentoEntity(
      row['id'] as int?,
      (row['ctname'] as String?) ?? '',
      TipoInstalacion.fromString(row['tipo_instalacion'] as String?),
      ubicacion,
      clientId: row['client_id'] as String,
    );

    entity.nombre = row['nombre'] as String?;
    entity.descripcion = (row['descripcion'] as String?) ?? '';
    entity.traza = row['traza'] as String?;
    entity.pkInicio = (row['pk_inicio'] as num?)?.toDouble();
    entity.pkFin = (row['pk_fin'] as num?)?.toDouble();
    entity.latInicio = (row['lat_inicio'] as num?)?.toDouble();
    entity.lngInicio = (row['lng_inicio'] as num?)?.toDouble();
    entity.latFin = (row['lat_fin'] as num?)?.toDouble();
    entity.lngFin = (row['lng_fin'] as num?)?.toDouble();
    entity.tipoActividad =
        TipoActividad.fromString(row['tipo_actividad'] as String?);
    entity.estado = EstadoActividad.fromString(row['estado'] as String?);
    entity.imagenes = _parseImagenes(row['imagenes_json'] as String?);
    entity.mensajes = _parseMensajes(row['mensajes_json'] as String?);

    final createdAtRaw = row['created_at'] as String?;
    entity.createdAt =
        createdAtRaw != null ? DateTime.tryParse(createdAtRaw) : null;

    final fechaInicioRaw = row['fecha_inicio'] as String?;
    entity.fechaInicio =
        fechaInicioRaw != null ? DateTime.tryParse(fechaInicioRaw) : null;

    final fechaFinRaw = row['fecha_fin'] as String?;
    entity.fechaFin =
        fechaFinRaw != null ? DateTime.tryParse(fechaFinRaw) : null;

    return entity;
  }

  static List<LatLng> _parseUbicacion(String? raw) {
    if (raw == null || raw.isEmpty) return const <LatLng>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> &&
          decoded['type'] == 'LineString' &&
          decoded['coordinates'] is List) {
        final coords = decoded['coordinates'] as List;
        return coords
            .whereType<List>()
            .map((c) => LatLng(
                  (c[1] as num).toDouble(),
                  (c[0] as num).toDouble(),
                ))
            .toList();
      }
    } catch (_) {}
    return const <LatLng>[];
  }

  static List<ImagenSegmentoEntity> _parseImagenes(String? raw) {
    if (raw == null || raw.isEmpty) return const <ImagenSegmentoEntity>[];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((m) => ImagenSegmentoEntity.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const <ImagenSegmentoEntity>[];
    }
  }

  static List<MensajeSegmentoEntity> _parseMensajes(String? raw) {
    if (raw == null || raw.isEmpty) return const <MensajeSegmentoEntity>[];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((m) => MensajeSegmentoEntity.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const <MensajeSegmentoEntity>[];
    }
  }
}
