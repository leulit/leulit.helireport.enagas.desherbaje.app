import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';

import '../../core/result/data_result.dart';
import '../../core/sync/sync.dart';
import '../model/mensaje_entity.dart';

/// Repository for [MensajeSegmentoEntity]. Fully offline-first, mirroring
/// imágenes/vídeos:
///
/// - **Reads** come from the local store by the owning segmento's `clientId`
///   ([getAllBySegmentoClientId]). The segmento pull embeds the backend
///   mensajes inside `segmento.mensajes[]`, so there is no online read.
/// - **Writes** route through the offline engine: a new mensaje lands in the
///   local store + outbox and is pushed on the next manual drain. Only NEW
///   mensajes carry an outbox job; embedded (backend) ones never do.
class MensajeSegmentoRepository {
  MensajeSegmentoRepository({
    OfflineRepository<MensajeSegmentoEntity>? offline,
  }) : _offline = offline ?? DI.get<OfflineRepository<MensajeSegmentoEntity>>();

  final OfflineRepository<MensajeSegmentoEntity> _offline;

  /// Local mensajes for a segmento, keyed by its stable local clientId.
  Future<List<MensajeSegmentoEntity>> getAllBySegmentoClientId(
    String segmentoClientId,
  ) =>
      _offline.findWhere('segmento_client_id', segmentoClientId);

  Future<DataResult<MensajeSegmentoEntity>> add({
    required int segmentoId,
    required String segmentoClientId,
    required String mensaje,
    required int enviadoPor,
  }) async {
    try {
      final entity = MensajeSegmentoEntity(
        segmentoId: segmentoId,
        segmentoClientId: segmentoClientId,
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
}
