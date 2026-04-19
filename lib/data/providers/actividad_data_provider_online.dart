import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import '../../core/result/data_result.dart';
import '../../data/network/network_error.dart';
import '../../data/network/network_service.dart';
import '../../domain/entities/actividad_entity.dart';
import 'actividad_data_provider.dart';

class ActividadDataProviderOnline implements ActividadDataProvider {
  final NetworkService _network = Get.find<NetworkService>();
  final _storage = const FlutterSecureStorage();

  Future<Map<String, String>?> _authHeader() async {
    final token = await _storage.read(key: 'auth_token');
    if (token == null) return null;
    return {'Authorization': 'Bearer $token'};
  }

  @override
  Future<DataResult<List<ActividadEntity>>> getByOperador(
      int operadorId, List<String> cts) async {
    try {
      final ctsCsv = cts.join(',');
      final path = '/actividades/operador/$ctsCsv';
      final response = await _network.get(path, headers: await _authHeader());
      final list = response.data as List? ?? [];
      final entities = list
          .map((e) => ActividadEntity.fromJson(e as Map<String, dynamic>))
          .toList();
      return DataResult.success(entities);
    } on NetworkError catch (e) {
      return DataResult.failure(
        message: 'Error de red al obtener actividades: ${e.message}',
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
  Future<DataResult<ActividadEntity?>> getById(int id) async {
    try {
      final path = '/actividades/byid/$id';
      final response = await _network.get(path, headers: await _authHeader());
      final data = response.data as Map<String, dynamic>;
      final item = data['data'];
      final entity =
          item == null ? null : ActividadEntity.fromJson(item as Map<String, dynamic>);
      return DataResult.success(entity);
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
      final path = '/actividades/update/$id';
      final response = await _network.post(
        path,
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
