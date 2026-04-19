import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../data/network/network_error.dart';
import '../../data/network/network_service.dart';
import '../../domain/entities/ct_info_entity.dart';
import '../../domain/entities/gasoducto_entity.dart';

class GasoductosDataProvider {
  final NetworkService _network = Get.find<NetworkService>();

  Future<List<GasoductoEntity>> loadForCt(CtInfo ctInfo) async {
    try {
      final response = await _network.get(
        ctInfo.gasoductosUrl,
        headers: const {'User-Agent': 'helireport-desherbaje'},
      );
      final data = response.data;
      final Map<String, dynamic> geoJson;
      if (data is String) {
        geoJson = jsonDecode(data) as Map<String, dynamic>;
      } else {
        geoJson = data as Map<String, dynamic>;
      }
      return compute(
        _parseGeoJson,
        _GeoJsonParseArgs(geoJson: geoJson, ctCode: ctInfo.ct),
      );
    } on NetworkError catch (e) {
      debugPrint('GasoductosDataProvider - Error cargando CT ${ctInfo.ct}: $e');
      return [];
    } catch (e) {
      debugPrint('GasoductosDataProvider - Error cargando CT ${ctInfo.ct}: $e');
      return [];
    }
  }

  Future<List<GasoductoEntity>> loadForCts(List<CtInfo> ctInfos) async {
    final results = <GasoductoEntity>[];
    for (final ct in ctInfos) {
      final gasoductos = await loadForCt(ct);
      results.addAll(gasoductos);
    }
    return results;
  }
}

class _GeoJsonParseArgs {
  final Map<String, dynamic> geoJson;
  final String ctCode;

  _GeoJsonParseArgs({required this.geoJson, required this.ctCode});
}

List<GasoductoEntity> _parseGeoJson(_GeoJsonParseArgs args) {
  return GasoductoEntity.fromGeoJson(args.geoJson, args.ctCode);
}
