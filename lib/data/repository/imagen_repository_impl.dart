import 'package:get/get.dart';

import '../../core/services/connectivity_service.dart';
import '../../core/sync/sync.dart';
import '../../domain/entities/imagen_segmento_entity.dart';

/// Repository for [ImagenSegmentoEntity]. All persistence routes through
/// the generic offline-first engine — both reads and writes.
///
/// Network uploads happen exclusively when the user asks for them (sync
/// page or per-entity "forzar envío"); this class never auto-triggers
/// drains.
class ImagenRepositoryImpl {
  ImagenRepositoryImpl({
    OfflineRepository<ImagenSegmentoEntity>? offline,
    SyncEngine? engine,
    ConnectivityService? connectivity,
  })  : _offline = offline ?? Get.find<OfflineRepository<ImagenSegmentoEntity>>(),
        _engine = engine ?? Get.find<SyncEngine>(),
        _connectivity = connectivity ?? Get.find<ConnectivityService>();

  final OfflineRepository<ImagenSegmentoEntity> _offline;
  final SyncEngine _engine;
  final ConnectivityService _connectivity;

  Future<void> saveLocal(ImagenSegmentoEntity imagen) =>
      _offline.create(imagen);

  Future<void> delete(ImagenSegmentoEntity imagen) =>
      _offline.delete(imagen);

  Future<List<ImagenSegmentoEntity>> getAllBySegmento(int segmentoId) =>
      _offline.findWhere('segmento_id', segmentoId);

  /// Drains ALL pending images through the generic sync engine.
  ///
  /// Returns an empty [DrainSummary] immediately when offline.
  Future<DrainSummary> uploadAllPending() async {
    if (!_connectivity.isConnected) return const DrainSummary();
    return _engine.drain(entityType: 'imagen');
  }
}
