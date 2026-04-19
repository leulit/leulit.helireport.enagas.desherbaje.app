import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../entities/ct_info_entity.dart';
import '../../data/repository/gasoductos_repository.dart';

class GetGasoductosUseCase {
  final GasoductosRepository _repo;

  GetGasoductosUseCase(this._repo);

  Future<List<Polyline>> execute({bool forceRefresh = false}) async {
    final ctInfos = await _getCtInfos();
    if (ctInfos.isEmpty) return [];
    return _repo.getPolylinesForCts(ctInfos, forceRefresh: forceRefresh);
  }

  Future<List<CtInfo>> _getCtInfos() async {
    final prefs = await SharedPreferences.getInstance();
    final ctInfosJson = prefs.getString('user_ct_infos');
    if (ctInfosJson != null) {
      try {
        final decoded = jsonDecode(ctInfosJson) as List<dynamic>;
        return decoded
            .map((e) => CtInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    final cts = prefs.getStringList('user_cts') ?? [];
    return cts.map(CtInfo.fromString).toList();
  }
}
