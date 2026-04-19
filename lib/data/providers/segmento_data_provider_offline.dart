import '../../core/result/data_result.dart';
import '../../data/local/local_database.dart';
import '../../domain/entities/segmento_entity.dart';
import '../sync/segmento_local_store.dart';
import 'segmento_data_provider.dart';

class SegmentoDataProviderOffline implements SegmentoDataProvider {
  final _db = LocalDatabase.instance;

  @override
  Future<DataResult<List<SegmentoEntity>>> getByOperador(
      int operadorId, List<int> cts) async {
    try {
      final db = await _db.database;
      final rows = await db.query('segmentos', orderBy: 'fecha_fin DESC');
      return DataResult.success(
        rows.map(SegmentoLocalStore.rowToEntity).toList(growable: false),
      );
    } catch (e) {
      return DataResult.failure(
        message: 'Error leyendo caché local: $e',
        statusCode: 0,
        cause: e,
      );
    }
  }

  @override
  Future<DataResult<SegmentoEntity?>> getById(int id) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'segmentos',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return DataResult.success(
        rows.isEmpty ? null : SegmentoLocalStore.rowToEntity(rows.first),
      );
    } catch (e) {
      return DataResult.failure(
        message: 'Error leyendo caché local: $e',
        statusCode: 0,
        cause: e,
      );
    }
  }

  @override
  Future<DataResult<bool>> updateEstado(int id, EstadoActividad estado) async {
    try {
      final db = await _db.database;
      final count = await db.update(
        'segmentos',
        {'estado': estado.descripcion, 'needs_sync': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      return DataResult.success(count > 0);
    } catch (e) {
      return DataResult.failure(
        message: 'Error actualizando caché local: $e',
        statusCode: 0,
        cause: e,
      );
    }
  }
}
