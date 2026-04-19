import '../../core/result/data_result.dart';
import '../../domain/entities/segmento_entity.dart';

abstract class SegmentoDataProvider {
  Future<DataResult<List<SegmentoEntity>>> getByOperador(
      int operadorId, List<int> cts);
  Future<DataResult<SegmentoEntity?>> getById(int id);
  Future<DataResult<bool>> updateEstado(int id, EstadoActividad estado);
}
