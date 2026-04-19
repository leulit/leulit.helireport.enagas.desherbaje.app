import 'package:shared_preferences/shared_preferences.dart';
import '../../core/result/data_result.dart';
import '../entities/actividad_entity.dart';
import '../repository/actividad_repository.dart';

class GetSegmentosUseCase {
  final ActividadRepository _repo;

  GetSegmentosUseCase(this._repo);

  Future<DataResult<List<ActividadEntity>>> execute() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 0;
    final cts = prefs.getStringList('user_cts') ?? [];
    return _repo.getByOperador(userId, cts);
  }
}
