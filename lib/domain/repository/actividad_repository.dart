import '../../core/result/data_result.dart';
import '../entities/actividad_entity.dart';

abstract class ActividadRepository {
  Future<DataResult<List<ActividadEntity>>> getByOperador(
      int operadorId, List<String> cts);
  Future<DataResult<ActividadEntity?>> getById(int id);
  Future<DataResult<bool>> updateEstado(int id, EstadoActividad estado);
}
