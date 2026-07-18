import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../../core/result/data_result.dart';
import '../entities/segmento_entity.dart';
import '../entities/user_entity.dart';
import '../repository/segmento_repository.dart';

class GetSegmentosUseCase {
  final SegmentoRepository _repo;

  GetSegmentosUseCase(this._repo);

  Future<DataResult<List<SegmentoEntity>>> execute() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 0;
    final ctNames = readCtNamesFromPrefs(prefs);
    return _repo.getByOperador(userId, ctNames);
  }
}

/// Nombres de CT del operador logueado, leídos del usuario persistido
/// (`user_json`, campo `UserCt.ct`). El segmento identifica su CT por NOMBRE
/// (contrato §3/§8: la descarga `GET /segmentos/contratista` filtra por nombre
/// de CT), así que el filtro local de lectura también va por nombre — misma
/// fuente que [SegmentoRemoteFetcher]. El plano `user_cts` (ctids) ya no sirve
/// para filtrar la tabla local.
List<String> readCtNamesFromPrefs(SharedPreferences prefs) {
  final raw = prefs.getString('user_json');
  if (raw == null || raw.isEmpty) return const <String>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return UserModel.fromJson(decoded)
          .ctsName()
          .where((n) => n.isNotEmpty)
          .toList();
    }
  } catch (_) {}
  return const <String>[];
}
