import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/sync/contracts/local_store.dart';
import '../../domain/entities/imagen_segmento_entity.dart';
import '../../domain/entities/segmento_entity.dart';
import '../model/mensaje_entity.dart';

/// SQLite-backed [LocalStore] for [SegmentoEntity].
///
/// Writes against the `segmentos` table defined in `LocalDatabase` (schema
/// v5). Every [upsert] flags the row as pending sync (`needs_sync = 1`);
/// [markSynced] is the only path that clears the flag.
class SegmentoLocalStore implements LocalStore<SegmentoEntity> {
  static const String _table = 'segmentos';
  static const String _clientIdPrefix = 'seg-';

  final Database _db;

  SegmentoLocalStore(this._db);

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
    final id = _parseClientId(clientId);
    final executor = txn ?? _db;
    await executor.delete(
      _table,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<SegmentoEntity?> findByClientId(String clientId) async {
    final id = _parseClientId(clientId);
    final rows = await _db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rowToEntity(rows.first);
  }

  @override
  Future<List<SegmentoEntity>> findAll() async {
    // SQLite doesn't support `NULLS LAST`; plain DESC puts NULLs first on
    // ASC and last on DESC — which matches what we want for recently-finished
    // segments first.
    final rows = await _db.query(_table, orderBy: 'fecha_fin DESC');
    return rows.map(rowToEntity).toList(growable: false);
  }

  @override
  Future<void> markSynced({
    required String clientId,
    String? remoteId,
    DatabaseExecutor? txn,
  }) async {
    final id = _parseClientId(clientId);
    final executor = txn ?? _db;
    await executor.update(
      _table,
      {
        'synced_at': DateTime.now().toIso8601String(),
        'needs_sync': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Public so the offline data provider can reuse the same row → entity
  /// mapping without duplicating code.
  static SegmentoEntity rowToEntity(Map<String, Object?> row) =>
      _SegmentoRowMapper.toEntity(row);

  /// Public so the offline data provider can reuse the same entity → row
  /// mapping.
  static Map<String, Object?> entityToRow(SegmentoEntity entity) =>
      _SegmentoRowMapper.toRow(entity);

  Map<String, Object?> _entityToRow(SegmentoEntity entity) =>
      _SegmentoRowMapper.toRow(entity);

  int _parseClientId(String clientId) {
    if (!clientId.startsWith(_clientIdPrefix)) {
      throw ArgumentError.value(
        clientId,
        'clientId',
        'Expected prefix "$_clientIdPrefix"',
      );
    }
    final raw = clientId.substring(_clientIdPrefix.length);
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      throw ArgumentError.value(
        clientId,
        'clientId',
        'Suffix "$raw" is not a valid integer id',
      );
    }
    return parsed;
  }
}

/// Centralises the row ↔ entity mapping so both [SegmentoLocalStore] and
/// `SegmentoDataProviderOffline` read/write rows the same way.
class _SegmentoRowMapper {
  static Map<String, Object?> toRow(SegmentoEntity e) => {
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
        'imagenes_json':
            jsonEncode(e.imagenes.map((i) => i.toJson()).toList()),
        'mensajes_json':
            jsonEncode(e.mensajes.map((m) => m.toJson()).toList()),
        'created_at': e.createdAt?.toIso8601String(),
        'fecha_inicio': e.fechaInicio?.toIso8601String(),
        'fecha_fin': e.fechaFin?.toIso8601String(),
        'needs_sync': 1,
      };

  static SegmentoEntity toEntity(Map<String, Object?> row) {
    final ubicacion = _parseUbicacion(row['ubicacion_gis'] as String?);

    final entity = SegmentoEntity(
      row['id'] as int?,
      (row['ct_id'] as int?) ?? 0,
      TipoInstalacion.fromString(row['tipo_instalacion'] as String?),
      ubicacion,
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

  static List<MensajeEntity> _parseMensajes(String? raw) {
    if (raw == null || raw.isEmpty) return const <MensajeEntity>[];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((m) => MensajeEntity.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const <MensajeEntity>[];
    }
  }
}
