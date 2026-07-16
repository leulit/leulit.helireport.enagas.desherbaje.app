import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final FlutterSecureStorage _storage;

  MensajeRemoteAdapter(
    this._network, {
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

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
      final prefs = await SharedPreferences.getInstance();
      final usuario = prefs.getString('user_usuario') ?? '';
      final userId = prefs.getInt('user_id') ?? 0;

      final body = <String, dynamic>{
        'client_id': entity.clientId,
        'segmento_id': entity.segmentoId,
        'usuariologged': usuario,
        'idusuariologged': userId,
        'mensaje': entity.mensaje,
        'enviado_por': entity.enviadoPor,
      };
      final response = await _network.post(
        ApiEndpoints.mensajeAdd(entity.segmentoId),
        body: body,
        headers: await bearerAuthHeader(_storage),
      );
      if (!response.isSuccess) {
        return SyncUnrecoverable<MensajeSegmentoEntity>(
          'HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      final data = response.data;
      String? remoteId;
      MensajeSegmentoEntity? serverVersion;
      if (data is Map) {
        final payload = data is Map<String, dynamic>
            ? data
            : data.cast<String, dynamic>();
        remoteId = extractRemoteIntId(payload)?.toString();
        try {
          serverVersion = MensajeSegmentoEntity.fromJson(payload);
        } catch (_) {
          serverVersion = null;
        }
      }
      return SyncSuccess<MensajeSegmentoEntity>(
        remoteId: remoteId,
        serverVersion: serverVersion,
      );
    } on NetworkError catch (e) {
      return syncOutcomeFromNetworkError<MensajeSegmentoEntity>(e);
    }
  }
}
