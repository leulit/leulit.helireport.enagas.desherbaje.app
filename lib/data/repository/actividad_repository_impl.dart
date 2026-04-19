import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../core/result/data_result.dart';
import '../../data/local/local_database.dart';
import '../providers/segmento_data_provider_factory.dart';
import '../../domain/entities/actividad_entity.dart';
import '../../domain/repository/actividad_repository.dart';

class ActividadRepositoryImpl implements ActividadRepository {
  final _db = LocalDatabase.instance;

  @override
  Future<DataResult<List<ActividadEntity>>> getByOperador(
      int operadorId, List<String> cts) async {
    final provider = SegmentoDataProviderFactory.create();
    final result = await provider.getByOperador(operadorId, cts);
    if (result.isSuccess) {
      await _cacheActividades(result.dataOrNull ?? []);
    }
    return result;
  }

  @override
  Future<DataResult<ActividadEntity?>> getById(int id) {
    final provider = SegmentoDataProviderFactory.create();
    return provider.getById(id);
  }

  @override
  Future<DataResult<bool>> updateEstado(int id, EstadoActividad estado) {
    final provider = SegmentoDataProviderFactory.create();
    return provider.updateEstado(id, estado);
  }

  Future<void> _cacheActividades(List<ActividadEntity> actividades) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final a in actividades) {
      batch.insert(
        'actividades',
        {
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
          'synced_at': DateTime.now().toIso8601String(),
          'needs_sync': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
