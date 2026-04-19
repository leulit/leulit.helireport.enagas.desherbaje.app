import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart' hide Response;
import '../../core/result/data_result.dart';
import '../../core/services/api_security_service.dart';
import '../../data/network/network_service.dart';
import '../../domain/entities/actividad_entity.dart';
import 'actividad_data_provider.dart';

class ActividadDataProviderOnline implements ActividadDataProvider {
  final Dio _dio = Get.find<NetworkService>().dio;
  final _storage = const FlutterSecureStorage();

  Future<String?> get _token => _storage.read(key: 'auth_token');

  @override
  Future<DataResult<List<ActividadEntity>>> getByOperador(
      int operadorId, List<String> cts) async {
    try {
      final ctsCsv = cts.join(',');
      final path = '/actividades/operador/$ctsCsv';
      final token = await _token;
      final headers = ApiSecurityService.buildHeaders('GET', path, token: token);
      final response = await _dio.get(path, options: Options(headers: headers));
      final list = response.data as List? ?? [];
      final entities = list
          .map((e) => ActividadEntity.fromJson(e as Map<String, dynamic>))
          .toList();
      return DataResult.success(entities);
    } on DioException catch (e) {
      return DataResult.failure(
        message: 'Error de red al obtener actividades',
        statusCode: e.response?.statusCode ?? 503,
        cause: e,
      );
    } catch (e) {
      return DataResult.failure(message: 'Error inesperado: $e', statusCode: 500, cause: e);
    }
  }

  @override
  Future<DataResult<ActividadEntity?>> getById(int id) async {
    try {
      final path = '/actividades/byid/$id';
      final token = await _token;
      final headers =
          ApiSecurityService.buildHeaders('GET', path, token: token);
      final response =
          await _dio.get(path, options: Options(headers: headers));
      final data = response.data as Map<String, dynamic>;
      final item = data['data'];
      final entity =
          item == null ? null : ActividadEntity.fromJson(item as Map<String, dynamic>);
      return DataResult.success(entity);
    } on DioException catch (e) {
      return DataResult.failure(
        message: e.response?.data?['message'] as String? ??
            'Error de red al obtener actividad',
        statusCode: e.response?.statusCode ?? 503,
        cause: e,
      );
    } catch (e) {
      return DataResult.failure(
          message: 'Error inesperado: $e', statusCode: 500, cause: e);
    }
  }

  @override
  Future<DataResult<bool>> updateEstado(int id, EstadoActividad estado) async {
    try {
      final path = '/actividades/update/$id';
      final token = await _token;
      final headers =
          ApiSecurityService.buildHeaders('POST', path, token: token);
      final response = await _dio.post(
        path,
        data: {'estado': estado.descripcion},
        options: Options(headers: headers),
      );
      final data = response.data as Map<String, dynamic>;
      return DataResult.success(data['success'] == true);
    } on DioException catch (e) {
      return DataResult.failure(
        message: e.response?.data?['message'] as String? ??
            'Error de red al actualizar estado',
        statusCode: e.response?.statusCode ?? 503,
        cause: e,
      );
    } catch (e) {
      return DataResult.failure(
          message: 'Error inesperado: $e', statusCode: 500, cause: e);
    }
  }
}
