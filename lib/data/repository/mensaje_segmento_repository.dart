import 'package:get/get.dart';

import '../../core/app_log.dart';
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
/// NF-16: any failure (network OR generic) falls back to local cache.
/// NF-17: empty cache is a valid success (not an error).
/// NF-18: dedup by cascading key: fast-path on clientId echo, fingerprint
///        fallback for interoperability before backend implements BE-2.
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
        // NF-16b: unexpected body format — fall back to cache.
        // Log via AppLog so contract regressions are visible in release builds.
        AppLog.w(
          'mensajesBySegmento($id): respuesta inesperada del backend '
          '(tipo: ${data.runtimeType}), sirviendo caché local',
        );
        return _serveCacheOrFail(
          id,
          reason: 'body-no-List',
          message:
              'Respuesta inesperada al cargar mensajes del segmento $id',
          statusCode: response.statusCode,
        );
      }
      // NF-16c: individual fromJson failures must not blow up the merge.
      final remote = <MensajeSegmentoEntity>[];
      for (final m in data.whereType<Map>()) {
        try {
          remote.add(
            MensajeSegmentoEntity.fromJson(m.cast<String, dynamic>()),
          );
        } catch (e, s) {
          AppLog.w(
            'mensajesBySegmento($id): fallo parseando un mensaje — se omite',
            error: e,
            stackTrace: s,
          );
        }
      }
      final local = await _localStore.findBySegmento(id);
      return DataResult.success(_mergeWithPending(remote, local));
    } on NetworkError catch (e) {
      return _serveCacheOrFail(
        id,
        reason: 'red',
        message: 'Error de red cargando mensajes: ${e.message}',
        statusCode: e.statusCode ?? 503,
        cause: e,
      );
    } catch (e, s) {
      AppLog.e(
        'mensajesBySegmento($id): excepción inesperada',
        error: e,
        stackTrace: s,
      );
      return _serveCacheOrFail(
        id,
        reason: 'inesperado',
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

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// NF-16 + NF-17: any fetch failure falls back to local cache.
  /// Empty cache → DataSuccess([]) (a segment with no messages is valid).
  /// If the store itself throws, that is the only irrecoverable path.
  Future<DataResult<List<MensajeSegmentoEntity>>> _serveCacheOrFail(
    int segmentoId, {
    required String reason,
    required String message,
    int statusCode = 503,
    Object? cause,
  }) async {
    try {
      final local = await _localStore.findBySegmento(segmentoId);
      // NF-17: empty list is a valid "no messages" state, not an error.
      return DataResult.success(local);
    } catch (storeError, storeStack) {
      AppLog.e(
        'mensajesBySegmento($segmentoId): '
        'fallo de red ($reason) y además el store lanzó — path irrecuperable',
        error: storeError,
        stackTrace: storeStack,
      );
      return DataResult.failure(
        message: message,
        statusCode: statusCode,
        cause: cause ?? storeError,
      );
    }
  }

  /// NF-18: dedup with cascading key.
  ///
  /// Fast-path: if the backend echoes `client_id` (BE-2), the
  /// `remoteClientIds` set deduplicates correctly.
  ///
  /// Fallback fingerprint: we build a content fingerprint for every remote
  /// item (regardless of whether it has an id) and also for every local
  /// pending item. A local pending message is dropped when:
  ///   (a) backend echoed our clientId — fast-path, O(1) set lookup, or
  ///   (b) a remote item shares the same content fingerprint — bridges the
  ///       interoperability gap before BE-2 lands.
  ///
  /// Key scheme — `_dedupKey`:
  ///   - Entity with a known remote id  → `r:<id>`  (stable remote identity)
  ///   - Entity with no remote id       → `c:<segmentoId>|<mensaje>|<createdAt UTC ISO8601>`
  ///
  /// For the fingerprint comparison we always use the `c:` variant of the
  /// remote item so that a pending local (`id==null`) with the same content
  /// matches the remote version (`id!=null`) via `_contentKey`.
  List<MensajeSegmentoEntity> _mergeWithPending(
    List<MensajeSegmentoEntity> remote,
    List<MensajeSegmentoEntity> local,
  ) {
    final remoteClientIds = remote.map((m) => m.clientId).toSet();
    // Content fingerprints of remote items — used to match pending locals
    // whose clientId wasn't echoed back by the backend.
    final remoteContentKeys = remote.map(_contentKey).toSet();

    final pendingOnly = local.where((m) {
      if (m.id != null) return false; // already synced — remote has it
      // Fast-path: backend echoed our clientId (BE-2)
      if (remoteClientIds.contains(m.clientId)) return false;
      // Fingerprint bridge: same content already present in remote
      if (remoteContentKeys.contains(_contentKey(m))) return false;
      return true;
    }).toList();

    if (pendingOnly.isEmpty) return remote;
    return [...pendingOnly, ...remote];
  }

  /// Content fingerprint — always the `c:` variant, regardless of remote id.
  ///
  /// Allows a local pending item (id==null) to be matched against a remote
  /// item (id!=null) that shares the same content.
  String _contentKey(MensajeSegmentoEntity m) =>
      'c:${m.segmentoId}|${m.mensaje}|${m.createdAt.toUtc().toIso8601String()}';
}
