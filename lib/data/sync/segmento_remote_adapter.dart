import '../../core/api_endpoints.dart';
import '../../core/sync/contracts/remote_adapter.dart';
import '../../core/sync/contracts/sync_job.dart';
import '../../domain/entities/segmento_entity.dart';
import '../network/network_error.dart';
import '../network/network_service.dart';
import '../network/sync_outcome_from_network_error.dart';
import 'adapter_support.dart';

/// [RemoteAdapter] for [SegmentoEntity].
///
/// Single insert-or-update path: `POST /segmentos/upsert` with `id` in the
/// body (`0` for a brand-new segmento, the existing backend id for an update).
/// The backend decides insert vs update from that value. `delete` is not
/// supported yet and comes back as [SyncUnrecoverable].
///
/// Un 401 NO es sesión caducada: esta API no tiene sesión, la firma HMAC es la
/// única autenticación (§1 del contrato), así que un 401 solo puede ser secreto
/// erróneo, reloj desfasado >5 min o path mal firmado. Por eso
/// [syncOutcomeFromNetworkError] lo mapea a [SyncUnrecoverable] y nunca a
/// [AuthExpiredException]: deslogar al operador por un desfase de reloj le
/// destruiría la sesión de campo.
class SegmentoRemoteAdapter extends RemoteAdapter<SegmentoEntity> {
  final NetworkService _network;

  SegmentoRemoteAdapter(this._network);

  @override
  Future<SyncOutcome<SegmentoEntity>> push({
    required SegmentoEntity entity,
    required SyncOperation operation,
  }) async {
    if (operation == SyncOperation.delete) {
      return SyncUnrecoverable<SegmentoEntity>(
        'Operation ${operation.name} not supported for segmento yet',
        errorMessageEs:
            'El servidor todavía no acepta esta operación para segmentos.',
      );
    }

    try {
      // Conjunto declarado en el backend (§3). Todo campo no declarado se
      // descarta en silencio con HTTP 200 (ajv removeAdditional: "all"), así
      // que enviar extras oculta pérdida de datos: solo van estas claves.
      final body = <String, dynamic>{
        // id > 0 => update; 0 => insert. Viaja en el body, nunca en el path.
        'id': entity.id ?? 0,
        'tipo_actividad': entity.tipoActividad.descripcion,
        'estado': entity.estado.descripcion,
        // El CT viaja por nombre, no por id (§3): el backend guarda `ctname`.
        'ctname': entity.ctname,
        'nombre': entity.nombre,
        'traza': entity.traza,
        'tipo_instalacion': entity.tipoInstalacion.asString,
        'pk_inicio': entity.pkInicio?.toString(),
        'pk_fin': entity.pkFin?.toString(),
        'lat_inicio': entity.latInicio,
        'lng_inicio': entity.lngInicio,
        'lat_fin': entity.latFin,
        'lng_fin': entity.lngFin,
        'descripcion': entity.descripcion,
        // `fecha_inico` NO es una errata: es el nombre real de la columna en el
        // backend (§3). Corregirlo a `fecha_inicio` lo convierte en un campo no
        // declarado y el valor se pierde sin error.
        'fecha_inico': entity.fechaInicio?.toIso8601String(),
        'fecha_fin': entity.fechaFin?.toIso8601String(),
        'ubicacion_gis': entity.ubicacionGisAsGeoJSON,
        'longitud': entity.longitud,
      };

      // Sin cabecera de Bearer: esta API no tiene token de sesión, el HMAC del
      // interceptor es la única autenticación (§1).
      final response = await _network.post(
        ApiEndpoints.segmentoUpsert,
        body: body,
      );

      if (!response.isSuccess || bodyIndicatesError(response.data)) {
        // Fallo por status HTTP o por error de negocio en el body (HTTP 200 +
        // `{ok:false}`/`error`). Ver convención en BACKEND_SEGMENTO_SYNC_ENDPOINTS.
        final msg = bodyErrorMessage(response.data);
        return SyncUnrecoverable<SegmentoEntity>(
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

      final newId = extractRemoteIntId(payload);
      if (newId != null) entity.id = newId;

      final resolvedId = newId ?? entity.id;
      if (resolvedId == null) {
        return SyncUnrecoverable<SegmentoEntity>(
          'El servidor no devolvió un id para el segmento',
          errorMessageEs:
              'El servidor no devolvió un identificador para el segmento.',
        );
      }

      return SyncSuccess<SegmentoEntity>(
        remoteId: resolvedId.toString(),
        serverVersion: entity,
      );
    } on NetworkError catch (err) {
      return syncOutcomeFromNetworkError<SegmentoEntity>(err);
    }
  }
}
