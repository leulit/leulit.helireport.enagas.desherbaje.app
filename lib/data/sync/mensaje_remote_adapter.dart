import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/api_endpoints.dart';
import '../../core/sync/contracts/remote_adapter.dart';
import '../../core/sync/contracts/sync_job.dart';
import '../model/mensaje_entity.dart';
import '../network/network_error.dart';
import '../network/network_service.dart';
import '../network/sync_outcome_from_network_error.dart';

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
      final body = <String, dynamic>{
        'client_id': entity.clientId,
        'segmento_id': entity.segmentoId,
        'mensaje': entity.mensaje,
        'enviado_por': entity.enviadoPor,
      };
      final response = await _network.post(
        ApiEndpoints.mensajeAdd(entity.segmentoId),
        body: body,
        headers: await _authHeader(),
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
      if (data is Map<String, dynamic>) {
        final raw = data['id'] ?? data['remote_id'];
        if (raw is int) {
          remoteId = raw.toString();
        } else if (raw is String) {
          remoteId = raw;
        }
        try {
          serverVersion = MensajeSegmentoEntity.fromJson(data);
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

  Future<Map<String, String>?> _authHeader() async {
    final token = await _storage.read(key: 'auth_token');
    if (token == null) return null;
    return {'Authorization': 'Bearer $token'};
  }
}
