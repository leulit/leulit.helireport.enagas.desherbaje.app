import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response;
import '../../data/network/network_service.dart';
import '../../domain/entities/ct_info_entity.dart';
import '../../domain/entities/gasoducto_entity.dart';

class GasoductosDataProvider {
  final Dio _dio = Get.find<NetworkService>().dio;

  Future<List<GasoductoEntity>> loadForCt(CtInfo ctInfo) async {
    try {
      final response = await _dio.get(
        ctInfo.gasoductosUrl,
        options: Options(
          headers: {'User-Agent': 'helireport-desherbaje'},
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final Map<String, dynamic> geoJson;
      if (response.data is String) {
        geoJson = jsonDecode(response.data as String) as Map<String, dynamic>;
      } else {
        geoJson = response.data as Map<String, dynamic>;
      }
      return compute(
        _parseGeoJson,
        _GeoJsonParseArgs(geoJson: geoJson, ctCode: ctInfo.ct),
      );
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
