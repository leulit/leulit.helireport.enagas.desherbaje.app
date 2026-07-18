import '../../core/api_endpoints.dart';
import '../../core/sync/contracts/remote_adapter.dart';
import '../../core/sync/contracts/sync_job.dart';
import '../model/mensaje_entity.dart';
import '../network/network_error.dart';
import '../network/network_service.dart';
import '../network/sync_outcome_from_network_error.dart';
import 'adapter_support.dart';

/// Push-only adapter for [MensajeSegmentoEntity]. Updates / deletes of
/// existing mensajes are not yet supported by the backend.
class MensajeRemoteAdapter extends RemoteAdapter<MensajeSegmentoEntity> {
  final NetworkService _network;

  MensajeRemoteAdapter(this._network);

  @override
  Future<SyncOutcome<MensajeSegmentoEntity>> push({
    required MensajeSegmentoEntity entity,
    required SyncOperation operation,
  }) async {
    if (operation != SyncOperation.create) {
      return SyncUnrecoverable<MensajeSegmentoEntity>(
        'Operation ${operation.name} not supported for mensaje yet',
        errorMessageEs:
            'El servidor todavía no acepta esta operación para mensajes.',
      );
    }

    try {
      // Solo los campos declarados por el backend: el resto lo descarta ajv
      // (`removeAdditional: "all"`) sin devolver error. El `segmento_id` del
      // body se ignora — manda el del path.
      final body = <String, dynamic>{
        'mensaje': entity.mensaje,
        'enviado_por': entity.enviadoPor,
      };
      // Sin cabecera de Bearer: esta API no tiene token de sesión, el HMAC del
      // interceptor es la única autenticación (§1).
      final response = await _network.post(
        ApiEndpoints.mensajeAdd(entity.segmentoId),
        body: body,
      );
      if (!response.isSuccess || bodyIndicatesError(response.data)) {
        final msg = bodyErrorMessage(response.data);
        return SyncUnrecoverable<MensajeSegmentoEntity>(
          msg ?? 'HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      final data = response.data;
      final payload = data is Map<String, dynamic>
          ? data
          : data is Map
              ? data.cast<String, dynamic>()
              : const <String, dynamic>{};

      // Se estampa el `id` sobre la entidad existente en vez de reconstruirla
      // desde la respuesta: `fromJson` acuñaría un clientId nuevo (el backend
      // no devuelve `client_id`) y dejaría `segmento_client_id` a null, con lo
      // que el upsert local crearía una fila huérfana en vez de actualizar.
      final remoteIntId = extractRemoteIntId(payload);
      if (remoteIntId != null) entity.id = remoteIntId;

      return SyncSuccess<MensajeSegmentoEntity>(
        remoteId: entity.id?.toString(),
        serverVersion: entity,
      );
    } on NetworkError catch (e) {
      return syncOutcomeFromNetworkError<MensajeSegmentoEntity>(e);
    }
  }
}
