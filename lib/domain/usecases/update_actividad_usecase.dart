import '../../core/result/data_result.dart';
import '../entities/actividad_entity.dart';
import '../repository/actividad_repository.dart';

class UpdateActividadUseCase {
  final ActividadRepository _repo;
  UpdateActividadUseCase(this._repo);

  Future<DataResult<bool>> execute(int id, EstadoActividad estado) =>
      _repo.updateEstado(id, estado);
}
