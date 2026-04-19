import 'package:get/get.dart';

import '../../core/api_endpoints.dart';
import '../../core/result/data_result.dart';
import '../model/mensaje_entity.dart';
import '../network/network_error.dart';
import '../network/network_service.dart';

/// Repositorio (online-only por ahora) para los mensajes de segmento.
/// Siguiendo el patrón de la web: devuelve `DataResult` y nunca lanza.
class MensajeSegmentoRepository {
  NetworkService get _network => Get.find<NetworkService>();

  Future<DataResult<List<MensajeSegmentoEntity>>> mensajesBySegmento({
    required int id,
  }) async {
    try {
      final response = await _network.get(ApiEndpoints.mensajesBySegmento(id));
      final data = response.data;
      if (data is List) {
        final items = data
            .whereType<Map>()
            .map((m) => MensajeSegmentoEntity.fromJson(
                  m.cast<String, dynamic>(),
                ))
            .toList();
        return DataResult.success(items);
      }
      return DataResult.failure(
        message: 'Respuesta inesperada al cargar mensajes del segmento $id',
        statusCode: response.statusCode,
      );
    } on NetworkError catch (e) {
      return DataResult.failure(
        message: 'Error de red cargando mensajes: ${e.message}',
        statusCode: e.statusCode ?? 503,
        cause: e,
      );
    } catch (e) {
      return DataResult.failure(
        message: 'Excepción consultando mensajes del segmento $id: $e',
        statusCode: 500,
        cause: e,
      );
    }
  }

  Future<DataResult<MensajeSegmentoEntity>> add({
    required int segmentoId,
    required String mensaje,
    required int enviadoPor,
  }) async {
    try {
      final response = await _network.post(
        ApiEndpoints.mensajeAdd(segmentoId),
        body: {
          'segmento_id': segmentoId,
          'mensaje': mensaje,
          'enviado_por': enviadoPor,
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return DataResult.success(MensajeSegmentoEntity.fromJson(data));
      }
      // Si el backend solo devuelve { success: true }, sintetizamos un mensaje
      // local para que la UI pueda mostrarlo igualmente.
      return DataResult.success(MensajeSegmentoEntity(
        segmentoId: segmentoId,
        mensaje: mensaje,
        enviadoPor: enviadoPor,
      ));
    } on NetworkError catch (e) {
      return DataResult.failure(
        message: 'Error de red enviando mensaje: ${e.message}',
        statusCode: e.statusCode ?? 503,
        cause: e,
      );
    } catch (e) {
      return DataResult.failure(
        message: 'Excepción enviando mensaje: $e',
        statusCode: 500,
        cause: e,
      );
    }
  }
}
