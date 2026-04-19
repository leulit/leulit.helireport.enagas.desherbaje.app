import 'dart:convert';
import '../../core/result/data_result.dart';
import '../../data/local/local_database.dart';
import '../../domain/entities/actividad_entity.dart';
import '../../domain/entities/segmento_entity.dart';
import 'actividad_data_provider.dart';

class ActividadDataProviderOffline implements ActividadDataProvider {
  final _db = LocalDatabase.instance;

  @override
  Future<DataResult<List<ActividadEntity>>> getByOperador(
      int operadorId, List<String> cts) async {
    try {
      final db = await _db.database;
      final rows = await db.query('actividades');
      return DataResult.success(rows.map(_rowToEntity).toList());
    } catch (e) {
      return DataResult.failure(
          message: 'Error leyendo caché local: $e', statusCode: 0, cause: e);
    }
  }

  @override
  Future<DataResult<ActividadEntity?>> getById(int id) async {
    try {
      final db = await _db.database;
      final rows =
          await db.query('actividades', where: 'id = ?', whereArgs: [id]);
      return DataResult.success(rows.isEmpty ? null : _rowToEntity(rows.first));
    } catch (e) {
      return DataResult.failure(
          message: 'Error leyendo caché local: $e', statusCode: 0, cause: e);
    }
  }

  @override
  Future<DataResult<bool>> updateEstado(int id, EstadoActividad estado) async {
    try {
      final db = await _db.database;
      final count = await db.update(
        'actividades',
        {'estado': estado.descripcion, 'needs_sync': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      return DataResult.success(count > 0);
    } catch (e) {
      return DataResult.failure(
          message: 'Error actualizando caché local: $e',
          statusCode: 0,
          cause: e);
    }
  }

  ActividadEntity _rowToEntity(Map<String, dynamic> row) {
    List<SegmentoEntity> segs = [];
    final segsJson = row['segmentos_json'] as String?;
    if (segsJson != null && segsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(segsJson) as List;
        segs = decoded
            .map((s) => SegmentoEntity.fromJson(s as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    return ActividadEntity(
      id: row['id'] as int,
      posicionId: row['posicion_id'] as int? ?? 0,
      estado: EstadoActividad.fromString(row['estado'] as String?),
      descripcion: row['descripcion'] as String? ?? '',
      superficieM2: (row['superficie_m2'] as num?)?.toDouble() ?? 0.0,
      costeEstimado: (row['coste_estimado'] as num?)?.toDouble() ?? 0.0,
      fechaProgramada:
          DateTime.tryParse(row['fecha_programada'] as String? ?? '') ??
              DateTime.now(),
      fechaInicio: DateTime.tryParse(row['fecha_inicio'] as String? ?? '') ??
          DateTime.now(),
      fechaFin: DateTime.tryParse(row['fecha_fin'] as String? ?? '') ??
          DateTime.now(),
      segmentos: segs,
    );
  }
}
