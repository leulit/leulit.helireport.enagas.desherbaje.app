import 'package:get/get.dart';

import '../../core/api_endpoints.dart';
import '../../core/result/data_result.dart';
import '../../core/sync/sync.dart';
import '../model/mensaje_entity.dart';
import '../network/network_error.dart';
import '../network/network_service.dart';
import '../sync/mensaje_local_store.dart';

/// Repository for [MensajeSegmentoEntity].
///
/// **Writes** route through the offline-first engine: the operator can send
/// a mensaje offline, it lands in the local store + outbox, and is pushed
/// during the next manual drain.
///
/// **Reads** are still online-first by `segmentoId` because the backend
/// currently has no global pull endpoint. The repository merges fresh data
/// with locally-pending mensajes (those not yet synced) so the operator
/// always sees what they just wrote, and falls back to local cache when
/// offline.
///
/// TODO(backend): expose `GET /mensajes?operador=X` so this repository can
/// pull all mensajes through `RemoteFetcher.pullAll()` and the lectura
/// becomes 100% local-first like every other entity.
class MensajeSegmentoRepository {
  MensajeSegmentoRepository({
    NetworkService? network,
    OfflineRepository<MensajeSegmentoEntity>? offline,
    MensajeLocalStore? localStore,
  })  : _network = network ?? Get.find<NetworkService>(),
        _offline =
            offline ?? Get.find<OfflineRepository<MensajeSegmentoEntity>>(),
        _localStore = localStore ?? Get.find<MensajeLocalStore>();

  final NetworkService _network;
  final OfflineRepository<MensajeSegmentoEntity> _offline;
  final MensajeLocalStore _localStore;

  Future<DataResult<List<MensajeSegmentoEntity>>> mensajesBySegmento({
    required int id,
  }) async {
    try {
      final response = await _network.get(ApiEndpoints.mensajesBySegmento(id));
      final data = response.data;
      if (data is! List) {
        return DataResult.failure(
          message: 'Respuesta inesperada al cargar mensajes del segmento $id',
          statusCode: response.statusCode,
        );
      }
      final remote = data
          .whereType<Map>()
          .map((m) => MensajeSegmentoEntity.fromJson(m.cast<String, dynamic>()))
          .toList();
      final local = await _localStore.findBySegmento(id);
      return DataResult.success(_mergeWithPending(remote, local));
    } on NetworkError catch (e) {
      // Falló la red: servimos sólo la cache local para que el operador no
      // se quede sin mensajes en campo.
      final local = await _localStore.findBySegmento(id);
      if (local.isNotEmpty) return DataResult.success(local);
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
      final entity = MensajeSegmentoEntity(
        segmentoId: segmentoId,
        mensaje: mensaje,
        enviadoPor: enviadoPor,
      );
      await _offline.create(entity);
      return DataResult.success(entity);
    } catch (e) {
      return DataResult.failure(
        message: 'No se ha podido encolar el mensaje: $e',
        cause: e,
      );
    }
  }

  /// Merges the backend list with locally-pending mensajes (those without
  /// `synced_at`). Pending mensajes are appended at the top so the operator
  /// always sees what they just wrote.
  List<MensajeSegmentoEntity> _mergeWithPending(
    List<MensajeSegmentoEntity> remote,
    List<MensajeSegmentoEntity> local,
  ) {
    final remoteClientIds =
        remote.map((m) => m.clientId).toSet();
    final pendingOnly = local
        .where((m) => m.id == null && !remoteClientIds.contains(m.clientId))
        .toList();
    if (pendingOnly.isEmpty) return remote;
    return [...pendingOnly, ...remote];
  }
}
