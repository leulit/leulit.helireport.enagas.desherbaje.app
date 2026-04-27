import 'package:get/get.dart';

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
  })  : _offline = offline ?? Get.find<OfflineRepository<ImagenSegmentoEntity>>(),
        _engine = engine ?? Get.find<SyncEngine>();

  final OfflineRepository<ImagenSegmentoEntity> _offline;
  final SyncEngine _engine;

  Future<void> saveLocal(ImagenSegmentoEntity imagen) =>
      _offline.create(imagen);

  Future<void> delete(ImagenSegmentoEntity imagen) =>
      _offline.delete(imagen);

  Future<List<ImagenSegmentoEntity>> getAllBySegmento(int segmentoId) async {
    final all = await _offline.findAll();
    return all.where((i) => i.segmentoId == segmentoId).toList();
  }

  Future<List<ImagenSegmentoEntity>> getPendingBySegmento(int segmentoId) async {
    final all = await _offline.findAll();
    return all
        .where((i) => i.segmentoId == segmentoId && i.subidaAt == null)
        .toList();
  }

  /// Pushes all pending images by routing through the generic engine.
  /// Note: drains every pending image, not just those of [segmentoId] —
  /// the engine doesn't filter by domain attributes. Kept signature for
  /// backwards compatibility with the existing controllers; will be
  /// replaced by a global sync page entry point.
  Future<DrainSummary> uploadPending(int segmentoId) =>
      _engine.drain(entityType: 'imagen');
}
