import '../../core/result/data_result.dart';
import '../entities/segmento_entity.dart';
import '../repository/segmento_repository.dart';

class UpdateSegmentoEstadoUseCase {
  final SegmentoRepository _repo;

  UpdateSegmentoEstadoUseCase(this._repo);

  Future<DataResult<bool>> execute(int id, EstadoActividad estado) =>
      _repo.updateEstado(id, estado);
}
