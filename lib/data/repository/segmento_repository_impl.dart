import 'package:sqflite/sqflite.dart';

import '../../core/result/data_result.dart';
import '../../data/local/local_database.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/repository/segmento_repository.dart';
import '../providers/segmento_data_provider_factory.dart';
import '../sync/segmento_local_store.dart';

class SegmentoRepositoryImpl implements SegmentoRepository {
  final _db = LocalDatabase.instance;

  @override
  Future<DataResult<List<SegmentoEntity>>> getByOperador(
    int operadorId,
    List<String> cts,
  ) async {
    final provider = SegmentoDataProviderFactory.create();
    final result = await provider.getByOperador(operadorId, cts);
    if (result.isSuccess) {
      await _cacheSegmentos(result.dataOrNull ?? const <SegmentoEntity>[]);
    }
    return result;
  }

  @override
  Future<DataResult<SegmentoEntity?>> getById(int id) {
    final provider = SegmentoDataProviderFactory.create();
    return provider.getById(id);
  }

  @override
  Future<DataResult<bool>> updateEstado(int id, EstadoActividad estado) {
    final provider = SegmentoDataProviderFactory.create();
    return provider.updateEstado(id, estado);
  }

  Future<void> _cacheSegmentos(List<SegmentoEntity> segmentos) async {
    if (segmentos.isEmpty) return;
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final s in segmentos) {
      final row = SegmentoLocalStore.entityToRow(s)
        ..['synced_at'] = now
        ..['needs_sync'] = 0;
      batch.insert(
        'segmentos',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
