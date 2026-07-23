import '../../core/api_endpoints.dart';
import '../../core/gis/capture_meta.dart';
import '../../core/gis/media_gis_geojson.dart';
import '../../core/sync/contracts/sync_progress.dart';
import '../../core/sync/pull/cancel_token.dart';
import '../../core/sync/contracts/remote_adapter.dart';
import '../../core/sync/contracts/sync_job.dart';
import '../../domain/entities/traza_entity.dart';
import '../network/network_error.dart';
import '../network/network_service.dart';
import '../network/sync_outcome_from_network_error.dart';
import 'adapter_support.dart';

/// Push-only adapter for [TrazaEntity]. Builds the track's GeoJSON
/// `FeatureCollection` and sends it as-is (decoded `Map`, not a `String`) to
/// `POST /positions/batch`, idempotent by `traza_client_id` per the backend
/// sync contract.
class TrazaRemoteAdapter extends RemoteAdapter<TrazaEntity> {
  final NetworkService _network;

  TrazaRemoteAdapter(this._network);

  @override
  Future<SyncOutcome<TrazaEntity>> push({
    required TrazaEntity entity,
    required SyncOperation operation,
    CancelToken? token,
    SyncProgressCallback? onProgress,
  }) async {
    if (operation != SyncOperation.create) {
      return SyncUnrecoverable<TrazaEntity>(
        'Operation ${operation.name} not supported for trazas',
        errorMessageEs:
            'El servidor solo acepta creación de trazas, no ${operation.name}.',
      );
    }

    final meta = await captureMeta();
    final body = buildTrackGeoJson(
      entity.points,
      userId: entity.operadorId,
      meta: meta,
      trazaClientId: entity.clientId,
      name: entity.name,
      startedAt: entity.startedAt,
      endedAt: entity.endedAt,
    );

    // Nothing survived the >60s-gap split — no point in a network round-trip.
    final features = body['features'] as List;
    final feature = features.first as Map<String, dynamic>;
    if (feature['geometry'] == null) {
      return const SyncSuccess<TrazaEntity>();
    }

    try {
      // Sin cabecera de Bearer: esta API no tiene token de sesión, el HMAC del
      // interceptor es la única autenticación (§1).
      final response = await _network.post(
        ApiEndpoints.positionsBatch,
        body: body,
      );
      if (!response.isSuccess) {
        return SyncUnrecoverable<TrazaEntity>(
          'HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      String? remoteId;
      final data = response.data;
      if (data is Map) {
        final payload =
            data is Map<String, dynamic> ? data : data.cast<String, dynamic>();
        remoteId = extractRemoteIntId(payload)?.toString();
      }
      return SyncSuccess<TrazaEntity>(remoteId: remoteId);
    } on NetworkError catch (e) {
      return syncOutcomeFromNetworkError<TrazaEntity>(e);
    }
  }
}
