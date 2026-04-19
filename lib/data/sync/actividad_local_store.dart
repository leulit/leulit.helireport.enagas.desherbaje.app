import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/sync/contracts/local_store.dart';
import '../../domain/entities/actividad_entity.dart';
import '../../domain/entities/segmento_entity.dart';

/// SQLite-backed [LocalStore] for [ActividadEntity].
///
/// Writes against the pre-existing `actividades` table defined in
/// `LocalDatabase`. Every [upsert] flags the row as pending sync
/// (`needs_sync = 1`); [markSynced] is the only path that clears the flag.
class ActividadLocalStore implements LocalStore<ActividadEntity> {
  static const String _table = 'actividades';
  static const String _clientIdPrefix = 'act-';

  final Database _db;

  ActividadLocalStore(this._db);

  @override
  Future<void> upsert(ActividadEntity entity, {DatabaseExecutor? txn}) async {
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
  Future<ActividadEntity?> findByClientId(String clientId) async {
    final id = _parseClientId(clientId);
    final rows = await _db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToEntity(rows.first);
  }

  @override
  Future<List<ActividadEntity>> findAll() async {
    final rows = await _db.query(
      _table,
      orderBy: 'fecha_programada DESC',
    );
    return rows.map(_rowToEntity).toList(growable: false);
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

  Map<String, Object?> _entityToRow(ActividadEntity a) => {
        'id': a.id,
        'posicion_id': a.posicionId,
        'estado': a.estado.descripcion,
        'descripcion': a.descripcion,
        'superficie_m2': a.superficieM2,
        'coste_estimado': a.costeEstimado,
        'fecha_programada': a.fechaProgramada.toIso8601String(),
        'fecha_inicio': a.fechaInicio.toIso8601String(),
        'fecha_fin': a.fechaFin.toIso8601String(),
        'segmentos_json':
            jsonEncode(a.segmentos.map((s) => s.toJson()).toList()),
        'needs_sync': 1,
      };

  ActividadEntity _rowToEntity(Map<String, Object?> row) {
    List<SegmentoEntity> segs = const <SegmentoEntity>[];
    final segsJson = row['segmentos_json'] as String?;
    if (segsJson != null && segsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(segsJson) as List;
        segs = decoded
            .map((s) => SegmentoEntity.fromJson(s as Map<String, dynamic>))
            .toList();
      } catch (_) {
        segs = const <SegmentoEntity>[];
      }
    }
    return ActividadEntity(
      id: row['id']! as int,
      posicionId: (row['posicion_id'] as int?) ?? 0,
      estado: EstadoActividad.fromString(row['estado'] as String?),
      descripcion: (row['descripcion'] as String?) ?? '',
      superficieM2: (row['superficie_m2'] as num?)?.toDouble() ?? 0.0,
      costeEstimado: (row['coste_estimado'] as num?)?.toDouble() ?? 0.0,
      fechaProgramada:
          DateTime.tryParse((row['fecha_programada'] as String?) ?? '') ??
              DateTime.now(),
      fechaInicio:
          DateTime.tryParse((row['fecha_inicio'] as String?) ?? '') ??
              DateTime.now(),
      fechaFin: DateTime.tryParse((row['fecha_fin'] as String?) ?? '') ??
          DateTime.now(),
      segmentos: segs,
    );
  }

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
