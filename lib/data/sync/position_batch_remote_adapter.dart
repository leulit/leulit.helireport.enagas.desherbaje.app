import '../../core/api_endpoints.dart';
import '../../core/sync/contracts/remote_adapter.dart';
import '../../core/sync/contracts/sync_job.dart';
import '../../domain/entities/position_batch_entity.dart';
import '../network/network_error.dart';
import '../network/network_service.dart';
import '../network/sync_outcome_from_network_error.dart';
import 'adapter_support.dart';

/// Push-only adapter for [PositionBatchEntity]. Sends an entire batch in a
/// single `POST /positions/batch` request, idempotent by
/// `batch_client_id` per the backend sync contract.
class PositionBatchRemoteAdapter extends RemoteAdapter<PositionBatchEntity> {
  final NetworkService _network;

  PositionBatchRemoteAdapter(this._network);

  @override
  Future<SyncOutcome<PositionBatchEntity>> push({
    required PositionBatchEntity entity,
    required SyncOperation operation,
  }) async {
    if (operation != SyncOperation.create) {
      return SyncUnrecoverable<PositionBatchEntity>(
        'Operation ${operation.name} not supported for position batches',
        errorMessageEs:
            'El servidor solo acepta creación de lotes GPS, no ${operation.name}.',
      );
    }
    if (entity.points.isEmpty) {
      return const SyncSuccess<PositionBatchEntity>();
    }

    try {
      // Sin cabecera de Bearer: esta API no tiene token de sesión, el HMAC del
      // interceptor es la única autenticación (§1).
      final response = await _network.post(
        ApiEndpoints.positionsBatch,
        body: entity.toJson(),
      );
      if (!response.isSuccess) {
        return SyncUnrecoverable<PositionBatchEntity>(
          'HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      String? remoteId;
      final data = response.data;
      if (data is Map) {
        final payload = data is Map<String, dynamic>
            ? data
            : data.cast<String, dynamic>();
        remoteId = extractRemoteIntId(payload)?.toString();
      }
      return SyncSuccess<PositionBatchEntity>(remoteId: remoteId);
    } on NetworkError catch (e) {
      return syncOutcomeFromNetworkError<PositionBatchEntity>(e);
    }
  }
}
