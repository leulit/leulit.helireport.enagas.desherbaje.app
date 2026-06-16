import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';

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
  int get schemaVersion => 1;

  @override
  Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    if (from == 0 && to == 1) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_table (
          client_id         TEXT PRIMARY KEY,
          id                INTEGER,
          ct_id             INTEGER NOT NULL DEFAULT 0,
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
          synced_at         TEXT
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${_table}_ct ON $_table(ct_id)',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_${_table}_remote '
        'ON $_table(id) WHERE id IS NOT NULL',
      );
    }
  }

  @override
  Future<void> upsert(SegmentoEntity entity, {DatabaseExecutor? txn}) async {
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

  /// Looks up a segmento by its (legacy / numeric) backend id. Returns null
  /// if the row hasn't been pulled yet.
  Future<SegmentoEntity?> findByRemoteId(int remoteId) async {
    final rows = await _db.query(
      _table,
      where: 'id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToEntity(rows.first);
  }

  /// Returns segmentos belonging to any of the given CTs.
  Future<List<SegmentoEntity>> findByCts(List<int> cts) async {
    if (cts.isEmpty) return const [];
    final placeholders = List.filled(cts.length, '?').join(',');
    final rows = await _db.query(
      _table,
      where: 'ct_id IN ($placeholders)',
      whereArgs: cts,
      orderBy: 'fecha_fin DESC',
    );
    return rows.map(_rowToEntity).toList(growable: false);
  }

  Map<String, Object?> _entityToRow(SegmentoEntity e) => {
        'client_id': e.clientId,
        'id': e.id,
        'ct_id': e.ctId,
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
      (row['ct_id'] as int?) ?? 0,
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
