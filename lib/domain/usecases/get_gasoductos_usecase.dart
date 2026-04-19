import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../entities/ct_info_entity.dart';
import '../entities/user_entity.dart';
import '../../data/repository/gasoductos_repository.dart';
import 'get_segmentos_usecase.dart' show readCtIdsFromPrefs;

class GetGasoductosUseCase {
  final GasoductosRepository _repo;

  GetGasoductosUseCase(this._repo);

  Future<List<Polyline>> execute({bool forceRefresh = false}) async {
    final ctInfos = await _getCtInfos();
    if (ctInfos.isEmpty) return [];
    return _repo.getPolylinesForCts(ctInfos, forceRefresh: forceRefresh);
  }

  /// Construye los `CtInfo` del usuario logueado desde el `UserModel`
  /// persistido. Si no hay usuario, cae al fallback de `user_cts` (lista
  /// plana de ids) sin nombre legible.
  Future<List<CtInfo>> _getCtInfos() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user_json');
    if (userJson != null) {
      try {
        final user =
            UserModel.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
        return user.cts
            .map((c) => CtInfo(id: c.ctid, nombre: c.ct, filename: c.ct))
            .toList();
      } catch (_) {}
    }
    return readCtIdsFromPrefs(prefs)
        .map((id) => CtInfo(id: id, nombre: '$id', filename: '$id'))
        .toList();
  }
}
