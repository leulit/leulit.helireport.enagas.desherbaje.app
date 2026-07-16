import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
/// Backend currently only supports `update`. `create` and `delete` come back
/// as [SyncUnrecoverable] until the backend exposes those operations.
///
/// The endpoint is `POST /segmentos/update/{id}` with the editable fields in
/// the body. 401 surfaces as [AuthExpiredException] via the helper.
class SegmentoRemoteAdapter extends RemoteAdapter<SegmentoEntity> {
  final NetworkService _network;
  final FlutterSecureStorage _storage;

  SegmentoRemoteAdapter(
    this._network, {
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<SyncOutcome<SegmentoEntity>> push({
    required SegmentoEntity entity,
    required SyncOperation operation,
  }) async {
    if (operation != SyncOperation.update) {
      return SyncUnrecoverable<SegmentoEntity>(
        'Operation ${operation.name} not supported for segmento yet',
        errorMessageEs:
            'El servidor todavía no acepta esta operación para segmentos.',
      );
    }
    final remoteId = entity.id;
    if (remoteId == null) {
      return SyncUnrecoverable<SegmentoEntity>(
        'Segmento sin id remoto: no puede actualizarse',
        errorMessageEs:
            'El segmento aún no existe en el servidor; no se puede actualizar.',
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final usuario = prefs.getString('user_usuario') ?? '';
      final userId = prefs.getInt('user_id') ?? 0;

      final body = <String, dynamic>{
        'client_id': entity.clientId,
        'segmento_id': remoteId,
        'usuariologged': usuario,
        'idusuariologged': userId,
        'estado': entity.estado.descripcion,
        if (entity.latInicio != null) 'lat_inicio': entity.latInicio,
        if (entity.lngInicio != null) 'lng_inicio': entity.lngInicio,
        if (entity.latFin != null) 'lat_fin': entity.latFin,
        if (entity.lngFin != null) 'lng_fin': entity.lngFin,
        if (entity.ubicacionGis.isNotEmpty)
          'ubicacion_gis': entity.ubicacionGisAsGeoJSON,
      };

      final response = await _network.post(
        ApiEndpoints.segmentoUpd(remoteId),
        body: body,
        headers: await bearerAuthHeader(_storage),
      );

      if (response.isSuccess && !bodyIndicatesError(response.data)) {
        return SyncSuccess<SegmentoEntity>(remoteId: remoteId.toString());
      }
      // Fallo por status HTTP o por error de negocio en el body (HTTP 200 +
      // `{ok:false}`/`error`). Ver convención en BACKEND_SEGMENTO_SYNC_ENDPOINTS.
      final msg = bodyErrorMessage(response.data);
      return SyncUnrecoverable<SegmentoEntity>(
        msg ?? 'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    } on NetworkError catch (err) {
      return syncOutcomeFromNetworkError<SegmentoEntity>(err);
    }
  }

}
