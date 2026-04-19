import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import '../../core/api_endpoints.dart';
import '../../core/result/data_result.dart';
import '../../data/network/network_error.dart';
import '../../data/network/network_service.dart';
import '../../domain/entities/segmento_entity.dart';
import 'segmento_data_provider.dart';

class SegmentoDataProviderOnline implements SegmentoDataProvider {
  final NetworkService _network = Get.find<NetworkService>();
  final _storage = const FlutterSecureStorage();

  Future<Map<String, String>?> _authHeader() async {
    final token = await _storage.read(key: 'auth_token');
    if (token == null) return null;
    return {'Authorization': 'Bearer $token'};
  }

  @override
  Future<DataResult<List<SegmentoEntity>>> getByOperador(
      int operadorId, List<int> cts) async {
    try {
      final ctsCsv = cts.join(',');
      final response = await _network.get(
        ApiEndpoints.segmentosByCt(ctsCsv),
        headers: await _authHeader(),
      );
      final raw = response.data as List? ?? const [];
      final entities = raw
          .whereType<Map>()
          .map((m) => SegmentoEntity.fromJson(m.cast<String, dynamic>()))
          .toList();
      return DataResult.success(entities);
    } on NetworkError catch (e) {
      return DataResult.failure(
        message: 'Error de red al obtener segmentos: ${e.message}',
        statusCode: e.statusCode ?? 503,
        cause: e,
      );
    } catch (e) {
      return DataResult.failure(
        message: 'Error inesperado: $e',
        statusCode: 500,
        cause: e,
      );
    }
  }

  @override
  Future<DataResult<SegmentoEntity?>> getById(int id) async {
    try {
      final response = await _network.get(
        ApiEndpoints.segmentoById(id),
        headers: await _authHeader(),
      );
      final body = response.data;
      if (body == null) return DataResult.success(null);

      // Soporta dos formas de respuesta: el segmento directo o envuelto en
      // `{data: {...}}` (legacy). Si llega lista, toma el primer elemento.
      Map<String, dynamic>? map;
      if (body is Map) {
        final inner = body['data'];
        if (inner is Map) {
          map = inner.cast<String, dynamic>();
        } else if (inner is List && inner.isNotEmpty && inner.first is Map) {
          map = (inner.first as Map).cast<String, dynamic>();
        } else {
          map = body.cast<String, dynamic>();
        }
      } else if (body is List && body.isNotEmpty && body.first is Map) {
        map = (body.first as Map).cast<String, dynamic>();
      }

      if (map == null) return DataResult.success(null);
      return DataResult.success(SegmentoEntity.fromJson(map));
    } on NetworkError catch (e) {
      return DataResult.failure(
        message: e.message,
        statusCode: e.statusCode ?? 503,
        cause: e,
      );
    } catch (e) {
      return DataResult.failure(
        message: 'Error inesperado: $e',
        statusCode: 500,
        cause: e,
      );
    }
  }

  @override
  Future<DataResult<bool>> updateEstado(int id, EstadoActividad estado) async {
    try {
      final response = await _network.post(
        ApiEndpoints.segmentoUpd(id),
        body: {'estado': estado.descripcion},
        headers: await _authHeader(),
      );
      final data = response.data as Map<String, dynamic>;
      return DataResult.success(data['success'] == true);
    } on NetworkError catch (e) {
      return DataResult.failure(
        message: e.message,
        statusCode: e.statusCode ?? 503,
        cause: e,
      );
    } catch (e) {
      return DataResult.failure(
        message: 'Error inesperado: $e',
        statusCode: 500,
        cause: e,
      );
    }
  }
}
