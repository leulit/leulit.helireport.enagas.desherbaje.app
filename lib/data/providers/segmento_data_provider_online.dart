import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

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
      int operadorId, List<String> cts) async {
    try {
      final ctsCsv = cts.join(',');
      final path = '/actividades/operador/$ctsCsv';
      final response = await _network.get(path, headers: await _authHeader());
      final raw = response.data as List? ?? const [];
      final entities = _flattenToSegmentos(raw);
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
      final path = '/actividades/byid/$id';
      final response = await _network.get(path, headers: await _authHeader());
      final data = response.data as Map<String, dynamic>;
      final item = data['data'];
      if (item == null) return DataResult.success(null);

      final map = (item as Map).cast<String, dynamic>();

      // The backend may still return a nested activity containing a list of
      // segments. If so, flatten and return the first segment (this endpoint
      // is called with a segment id, so the server response is expected to
      // contain that single segment).
      if (_isNestedActividad(map)) {
        final flat = _flattenToSegmentos([map]);
        return DataResult.success(flat.isEmpty ? null : flat.first);
      }

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

  /// Converts the backend list into a flat `List<SegmentoEntity>`.
  ///
  /// Supports two shapes for backend compatibility:
  /// 1. **Flat**: each element is already a segment JSON object.
  /// 2. **Nested** (legacy): each element is an actividad containing a
  ///    `segmentos: [...]` list. Activity-level fields (`estado`,
  ///    `tipo_actividad`, `fecha_inicio`, `fecha_fin`, `created_at`) are
  ///    merged into every child segment before parsing.
  List<SegmentoEntity> _flattenToSegmentos(List raw) {
    final result = <SegmentoEntity>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();

      if (_isNestedActividad(map)) {
        final actFields = <String, dynamic>{
          'estado': map['estado'],
          'tipo_actividad': map['tipo_actividad'],
          'fecha_inicio': map['fecha_inicio'],
          'fecha_fin': map['fecha_fin'],
          'created_at': map['created_at'],
        };
        for (final seg in (map['segmentos'] as List)) {
          if (seg is! Map) continue;
          final merged = <String, dynamic>{
            ...seg.cast<String, dynamic>(),
            // Only merge activity-level fields when the segment payload does
            // not already provide them — prefer segment-level data.
            for (final entry in actFields.entries)
              if (entry.value != null && !seg.containsKey(entry.key))
                entry.key: entry.value,
          };
          result.add(SegmentoEntity.fromJson(merged));
        }
      } else {
        result.add(SegmentoEntity.fromJson(map));
      }
    }
    return result;
  }

  bool _isNestedActividad(Map<String, dynamic> map) =>
      map['segmentos'] is List;
}
