import 'package:flutter/foundation.dart';

import '../../domain/entities/imagen_segmento_entity.dart';
import '../../domain/entities/video_segmento_entity.dart';

/// Unified presentation view-model for a single media item (photo or video)
/// shown in the Antes/Despues carousel. Collapses the three backing sources —
/// cloud imagen, cloud video (both ImagenSegmentoEntity), and local video
/// (VideoSegmentoEntity) — onto ONE type. The widget branches only on [isVideo]
/// and on which of [localPath]/[remoteUrl] is present; it never inspects the
/// backing entity type.
@immutable
class SegmentoMediaItem {
  final TipoFoto tipo;
  final bool isVideo;
  final String? remoteUrl; // raw imagen/video url (may be relative); null if none
  final String? localPath; // local file path (ruta); null/empty if cloud-only
  final String filename;
  final String clientId;
  final DateTime capturadaAt;
  final bool isSubida;
  final VoidCallback? onDelete; // null => not deletable (cloud or already uploaded)

  const SegmentoMediaItem({
    required this.tipo,
    required this.isVideo,
    required this.filename,
    required this.clientId,
    required this.capturadaAt,
    required this.isSubida,
    this.remoteUrl,
    this.localPath,
    this.onDelete,
  });

  factory SegmentoMediaItem.imagen(ImagenSegmentoEntity i, {VoidCallback? onDelete}) =>
      SegmentoMediaItem(
        tipo: i.tipoFoto,
        isVideo: false,
        filename: i.filename,
        clientId: i.clientId,
        capturadaAt: i.capturadaAt,
        isSubida: i.isSubida,
        remoteUrl: (i.url != null && i.url!.isNotEmpty) ? i.url : null,
        localPath: i.ruta.isNotEmpty ? i.ruta : null,
        onDelete: onDelete,
      );

  /// Cloud video: an ImagenSegmentoEntity whose media is a video (mime video/* or
  /// video extension). Playback is remote; never deletable from the field app.
  factory SegmentoMediaItem.remoteVideo(ImagenSegmentoEntity i) => SegmentoMediaItem(
        tipo: i.tipoFoto,
        isVideo: true,
        filename: i.filename,
        clientId: i.clientId,
        capturadaAt: i.capturadaAt,
        isSubida: true,
        remoteUrl: (i.url != null && i.url!.isNotEmpty) ? i.url : null,
        localPath: i.ruta.isNotEmpty ? i.ruta : null,
        onDelete: null,
      );

  factory SegmentoMediaItem.localVideo(VideoSegmentoEntity v, {VoidCallback? onDelete}) {
    final tipo = v.tipoVideo == TipoVideo.antes ? TipoFoto.antes : TipoFoto.despues;
    return SegmentoMediaItem(
      tipo: tipo,
      isVideo: true,
      filename: v.filename,
      clientId: v.clientId,
      capturadaAt: v.capturadaAt,
      isSubida: v.isSubida,
      remoteUrl: (v.url != null && v.url!.isNotEmpty) ? v.url : null,
      localPath: v.ruta.isNotEmpty ? v.ruta : null,
      onDelete: onDelete,
    );
  }
}
