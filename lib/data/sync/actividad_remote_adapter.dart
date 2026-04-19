import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/sync/contracts/remote_adapter.dart';
import '../../core/sync/contracts/sync_job.dart';
import '../../domain/entities/actividad_entity.dart';
import '../network/network_error.dart';
import '../network/network_service.dart';
import '../network/sync_outcome_from_network_error.dart';

/// [RemoteAdapter] for [ActividadEntity].
///
/// The backend owns creation; the app only pushes `update` to change
/// `estado`. `create`/`delete` are explicitly rejected as unrecoverable.
///
/// Conflicts (`NetworkErrorCategory.conflict`) are currently reported as
/// [SyncUnrecoverable] because the backend response body for this endpoint
/// has no known shape to rebuild the server version from. Replace with a
/// proper parser + [SyncConflict] once that contract is defined.
class ActividadRemoteAdapter extends RemoteAdapter<ActividadEntity> {
  final NetworkService _network;
  final FlutterSecureStorage _storage;

  ActividadRemoteAdapter(
    this._network, {
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<SyncOutcome<ActividadEntity>> push({
    required ActividadEntity entity,
    required SyncOperation operation,
  }) async {
    if (operation != SyncOperation.update) {
      return SyncUnrecoverable<ActividadEntity>(
        'Operation not supported for ActividadEntity: ${operation.name}',
      );
    }

    try {
      final response = await _network.post(
        '/actividades/update/${entity.id}',
        body: {'estado': entity.estado.descripcion},
        headers: await _authHeader(),
      );

      if (response.isSuccess) {
        return SyncSuccess<ActividadEntity>(remoteId: entity.id.toString());
      }
      return SyncUnrecoverable<ActividadEntity>(
        'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    } on NetworkError catch (err) {
      if (err.category == NetworkErrorCategory.conflict) {
        return SyncUnrecoverable<ActividadEntity>(
          'Conflict on actividad update (no server version parsing implemented)',
          statusCode: err.statusCode,
        );
      }
      return syncOutcomeFromNetworkError<ActividadEntity>(err);
    }
  }

  Future<Map<String, String>?> _authHeader() async {
    final token = await _storage.read(key: 'auth_token');
    if (token == null) return null;
    return {'Authorization': 'Bearer $token'};
  }
}
