import 'package:uuid/uuid.dart';

import '../../core/sync/contracts/syncable.dart';
import '../../data/model/json_parsing_utils.dart';

/// Tipo de vídeo: antes o después del trabajo.
enum TipoVideo {
  antes('antes', 'Antes'),
  despues('despues', 'Después');

  final String valor;
  final String etiqueta;

  const TipoVideo(this.valor, this.etiqueta);

  static TipoVideo fromString(String? value) {
    return TipoVideo.values.firstWhere(
      (e) => e.valor == value,
      orElse: () => TipoVideo.antes,
    );
  }
}

/// Nombres de campos mapeados a la tabla `videos_segmento` (backend + cache).
enum VideoSegmentoFieldNames {
  id('id'),
  clientId('client_id'),
  actividadId('actividad_id'),
  segmentoId('segmento_id'),
  tipoVideo('tipo_video'),
  filename('filename'),
  ruta('ruta'),
  url('url'),
  mimeType('mime_type'),
  tamanyoBytes('tamanyo_bytes'),
  latitud('latitud'),
  longitud('longitud'),
  fixedLatitud('fixed_latitud'),
  fixedLongitud('fixed_longitud'),
  capturadaAt('capturada_at'),
  subidaAt('subida_at'),
  subidaPor('subida_por'),
  createdAt('created_at'),
  updatedAt('updated_at'),
  syncedAt('synced_at'),
  needsSync('needs_sync'),
  uploadOffset('upload_offset'),
  /// Server-assigned upload session ID (UUID). Persisted after `initVideoUpload`
  /// to allow resuming across app restarts. NOT sent to the backend as part of
  /// the entity JSON payload.
  uploadId('upload_id');

  final String value;
  const VideoSegmentoFieldNames(this.value);
}

/// Entidad que representa un vídeo capturado en campo. Mapea 1:1 contra la
/// tabla local `videos_segmento` y contra el endpoint del backend.
///
/// Soporta subida chunked resumable: [uploadOffset] almacena el último byte
/// confirmado por el backend. El motor outbox reanuda desde ese punto en lugar
/// de reenviar el fichero completo.
class VideoSegmentoEntity implements Syncable {
  VideoSegmentoEntity({
    required this.actividadId,
    required this.segmentoId,
    required this.tipoVideo,
    required this.filename,
    required this.ruta,
    required this.capturadaAt,
    String? clientId,
  }) : _clientId = clientId ?? const Uuid().v4();

  /// Identificador remoto asignado por el backend tras la subida.
  int? id;

  /// Identificador estable generado en cliente. Persistido en `client_id`
  /// para que el outbox sea idempotente cuando aún no existe `id` remoto.
  final String _clientId;

  int actividadId;
  int segmentoId;
  TipoVideo tipoVideo;
  String filename;

  /// Ruta del fichero. Local mientras `subidaAt == null`; ruta servidor tras
  /// la subida.
  String ruta;
  String? url;
  String mimeType = 'video/mp4';
  int? tamanyoBytes;
  double? latitud;
  double? longitud;
  double? fixedLatitud;
  double? fixedLongitud;
  DateTime capturadaAt;
  DateTime? subidaAt;
  int? subidaPor;
  DateTime? createdAt;
  DateTime? updatedAtRemote;

  /// Offset en bytes ya confirmados por el backend en la sesión de subida
  /// chunked. Persiste en SQLite; permite reanudar la subida sin reenviar.
  int uploadOffset = 0;

  /// Server-assigned upload session ID returned by `POST /api/enagas/v1/videos/upload`.
  /// Null until the first successful init. Persisted via [VideoLocalStore.saveUploadId]
  /// immediately after init so the session can be resumed across app restarts.
  /// NOT included in [toJson] (not a backend entity field).
  String? uploadId;

  bool get isSubida => subidaAt != null;
  bool get isAntes => tipoVideo == TipoVideo.antes;
  bool get isDespues => tipoVideo == TipoVideo.despues;

  String get tamanyoLegible {
    final bytes = tamanyoBytes;
    if (bytes == null) return 'Desconocido';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  // ──────────────────────────── Syncable ────────────────────────────

  @override
  String get clientId => _clientId;

  /// Returns [uploadId] when available (the session UUID assigned by the video
  /// backend). Falls back to the legacy integer [id] as string. The outbox
  /// engine passes this to [VideoLocalStore.markSynced] after a successful push.
  @override
  String? get remoteId => uploadId ?? id?.toString();

  @override
  DateTime get updatedAt => updatedAtRemote ?? subidaAt ?? capturadaAt;

  // ──────────────────────────── JSON (backend) ────────────────────────────

  /// Constructor desde JSON del backend. [uploadOffset] NO se incluye en
  /// el payload del backend: es un campo de control interno del cliente.
  factory VideoSegmentoEntity.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String field, DateTime fallback) {
      try {
        final raw = json[field];
        if (raw == null) return fallback;
        return DateTime.parse(raw.toString());
      } catch (_) {
        return fallback;
      }
    }

    final entity = VideoSegmentoEntity(
      actividadId: readJsonDataUtil<int>(json, VideoSegmentoFieldNames.actividadId.value, 0),
      segmentoId:  readJsonDataUtil<int>(json, VideoSegmentoFieldNames.segmentoId.value, 0),
      tipoVideo:   TipoVideo.fromString(readJsonDataUtil<String?>(json, VideoSegmentoFieldNames.tipoVideo.value, null)),
      filename:    readJsonDataUtil<String>(json, VideoSegmentoFieldNames.filename.value, ''),
      ruta:        readJsonDataUtil<String>(json, VideoSegmentoFieldNames.ruta.value, ''),
      capturadaAt: parseDate(VideoSegmentoFieldNames.capturadaAt.value, DateTime.now()),
      clientId:    readJsonDataUtil<String?>(json, VideoSegmentoFieldNames.clientId.value, null),
    );

    entity.id           = readJsonDataUtil<int?>(json, VideoSegmentoFieldNames.id.value, null);
    entity.url          = readJsonDataUtil<String?>(json, VideoSegmentoFieldNames.url.value, null);
    entity.mimeType     = readJsonDataUtil<String>(json, VideoSegmentoFieldNames.mimeType.value, 'video/mp4');
    entity.tamanyoBytes = readJsonDataUtil<int?>(json, VideoSegmentoFieldNames.tamanyoBytes.value, null);
    entity.latitud       = (readJsonDataUtil<num?>(json, VideoSegmentoFieldNames.latitud.value, null))?.toDouble();
    entity.longitud      = (readJsonDataUtil<num?>(json, VideoSegmentoFieldNames.longitud.value, null))?.toDouble();
    entity.fixedLatitud  = (readJsonDataUtil<num?>(json, VideoSegmentoFieldNames.fixedLatitud.value, null))?.toDouble();
    entity.fixedLongitud = (readJsonDataUtil<num?>(json, VideoSegmentoFieldNames.fixedLongitud.value, null))?.toDouble();
    entity.subidaPor     = readJsonDataUtil<int?>(json, VideoSegmentoFieldNames.subidaPor.value, null);

    try {
      final subidaRaw = json[VideoSegmentoFieldNames.subidaAt.value];
      if (subidaRaw != null) entity.subidaAt = DateTime.parse(subidaRaw.toString());
    } catch (_) {}

    try {
      final createdRaw = json[VideoSegmentoFieldNames.createdAt.value];
      if (createdRaw != null) entity.createdAt = DateTime.parse(createdRaw.toString());
    } catch (_) {}

    try {
      final updatedRaw = json[VideoSegmentoFieldNames.updatedAt.value];
      if (updatedRaw != null) entity.updatedAtRemote = DateTime.parse(updatedRaw.toString());
    } catch (_) {}

    return entity;
  }

  /// Payload enviado al backend. [uploadOffset] se omite intencionalmente:
  /// es un campo de control interno del cliente, no del protocolo remoto.
  @override
  Map<String, dynamic> toJson() => {
        VideoSegmentoFieldNames.id.value: id,
        VideoSegmentoFieldNames.clientId.value: clientId,
        VideoSegmentoFieldNames.actividadId.value: actividadId,
        VideoSegmentoFieldNames.segmentoId.value: segmentoId,
        VideoSegmentoFieldNames.tipoVideo.value: tipoVideo.valor,
        VideoSegmentoFieldNames.filename.value: filename,
        VideoSegmentoFieldNames.ruta.value: ruta,
        VideoSegmentoFieldNames.url.value: url,
        VideoSegmentoFieldNames.mimeType.value: mimeType,
        VideoSegmentoFieldNames.tamanyoBytes.value: tamanyoBytes,
        VideoSegmentoFieldNames.latitud.value: latitud,
        VideoSegmentoFieldNames.longitud.value: longitud,
        VideoSegmentoFieldNames.fixedLatitud.value: fixedLatitud,
        VideoSegmentoFieldNames.fixedLongitud.value: fixedLongitud,
        VideoSegmentoFieldNames.capturadaAt.value: capturadaAt.toIso8601String(),
        VideoSegmentoFieldNames.subidaAt.value: subidaAt?.toIso8601String(),
        VideoSegmentoFieldNames.subidaPor.value: subidaPor,
      };

  // ──────────────────────────── SQLite map ────────────────────────────

  /// Mapa para la tabla local `videos_segmento`. Incluye [uploadOffset]
  /// (control de reanudación de subida chunked) y los campos de sincronía.
  Map<String, Object?> toMap({bool needsSync = true}) => {
        VideoSegmentoFieldNames.id.value: id,
        VideoSegmentoFieldNames.clientId.value: clientId,
        VideoSegmentoFieldNames.actividadId.value: actividadId,
        VideoSegmentoFieldNames.segmentoId.value: segmentoId,
        VideoSegmentoFieldNames.tipoVideo.value: tipoVideo.valor,
        VideoSegmentoFieldNames.filename.value: filename,
        VideoSegmentoFieldNames.ruta.value: ruta,
        VideoSegmentoFieldNames.url.value: url,
        VideoSegmentoFieldNames.mimeType.value: mimeType,
        VideoSegmentoFieldNames.tamanyoBytes.value: tamanyoBytes,
        VideoSegmentoFieldNames.latitud.value: latitud,
        VideoSegmentoFieldNames.longitud.value: longitud,
        VideoSegmentoFieldNames.fixedLatitud.value: fixedLatitud,
        VideoSegmentoFieldNames.fixedLongitud.value: fixedLongitud,
        VideoSegmentoFieldNames.capturadaAt.value: capturadaAt.toIso8601String(),
        VideoSegmentoFieldNames.subidaAt.value: subidaAt?.toIso8601String(),
        VideoSegmentoFieldNames.subidaPor.value: subidaPor,
        VideoSegmentoFieldNames.createdAt.value: createdAt?.toIso8601String(),
        VideoSegmentoFieldNames.updatedAt.value: updatedAtRemote?.toIso8601String(),
        VideoSegmentoFieldNames.needsSync.value: needsSync ? 1 : 0,
        VideoSegmentoFieldNames.uploadOffset.value: uploadOffset,
        VideoSegmentoFieldNames.uploadId.value: uploadId,
      };

  factory VideoSegmentoEntity.fromMap(Map<String, Object?> row) {
    DateTime parseDateOr(String field, DateTime fallback) {
      final raw = row[field];
      if (raw == null) return fallback;
      return DateTime.tryParse(raw.toString()) ?? fallback;
    }

    DateTime? parseDateNullable(String field) {
      final raw = row[field];
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    final entity = VideoSegmentoEntity(
      actividadId: (row[VideoSegmentoFieldNames.actividadId.value] as int?) ?? 0,
      segmentoId:  (row[VideoSegmentoFieldNames.segmentoId.value] as int?) ?? 0,
      tipoVideo:   TipoVideo.fromString(row[VideoSegmentoFieldNames.tipoVideo.value] as String?),
      filename:    (row[VideoSegmentoFieldNames.filename.value] as String?) ?? '',
      ruta:        (row[VideoSegmentoFieldNames.ruta.value] as String?) ?? '',
      capturadaAt: parseDateOr(VideoSegmentoFieldNames.capturadaAt.value, DateTime.now()),
      clientId:    row[VideoSegmentoFieldNames.clientId.value] as String?,
    );

    entity.id            = row[VideoSegmentoFieldNames.id.value] as int?;
    entity.url           = row[VideoSegmentoFieldNames.url.value] as String?;
    entity.mimeType      = (row[VideoSegmentoFieldNames.mimeType.value] as String?) ?? 'video/mp4';
    entity.tamanyoBytes  = row[VideoSegmentoFieldNames.tamanyoBytes.value] as int?;
    entity.latitud       = (row[VideoSegmentoFieldNames.latitud.value] as num?)?.toDouble();
    entity.longitud      = (row[VideoSegmentoFieldNames.longitud.value] as num?)?.toDouble();
    entity.fixedLatitud  = (row[VideoSegmentoFieldNames.fixedLatitud.value] as num?)?.toDouble();
    entity.fixedLongitud = (row[VideoSegmentoFieldNames.fixedLongitud.value] as num?)?.toDouble();
    entity.subidaPor     = row[VideoSegmentoFieldNames.subidaPor.value] as int?;
    entity.subidaAt        = parseDateNullable(VideoSegmentoFieldNames.subidaAt.value);
    entity.createdAt       = parseDateNullable(VideoSegmentoFieldNames.createdAt.value);
    entity.updatedAtRemote = parseDateNullable(VideoSegmentoFieldNames.updatedAt.value);
    entity.uploadOffset    = (row[VideoSegmentoFieldNames.uploadOffset.value] as int?) ?? 0;
    entity.uploadId        = row[VideoSegmentoFieldNames.uploadId.value] as String?;

    return entity;
  }

  VideoSegmentoEntity copyWith({
    int? id,
    int? actividadId,
    int? segmentoId,
    TipoVideo? tipoVideo,
    String? filename,
    String? ruta,
    String? url,
    String? mimeType,
    int? tamanyoBytes,
    double? latitud,
    double? longitud,
    double? fixedLatitud,
    double? fixedLongitud,
    DateTime? capturadaAt,
    DateTime? subidaAt,
    int? subidaPor,
    int? uploadOffset,
    String? uploadId,
  }) {
    final e = VideoSegmentoEntity(
      actividadId: actividadId ?? this.actividadId,
      segmentoId:  segmentoId  ?? this.segmentoId,
      tipoVideo:   tipoVideo   ?? this.tipoVideo,
      filename:    filename    ?? this.filename,
      ruta:        ruta        ?? this.ruta,
      capturadaAt: capturadaAt ?? this.capturadaAt,
      clientId:    clientId,
    );
    e.id           = id           ?? this.id;
    e.url          = url          ?? this.url;
    e.mimeType     = mimeType     ?? this.mimeType;
    e.tamanyoBytes = tamanyoBytes ?? this.tamanyoBytes;
    e.latitud       = latitud       ?? this.latitud;
    e.longitud      = longitud      ?? this.longitud;
    e.fixedLatitud  = fixedLatitud  ?? this.fixedLatitud;
    e.fixedLongitud = fixedLongitud ?? this.fixedLongitud;
    e.subidaAt      = subidaAt      ?? this.subidaAt;
    e.subidaPor     = subidaPor     ?? this.subidaPor;
    e.createdAt     = createdAt;
    e.updatedAtRemote = updatedAtRemote;
    e.uploadOffset  = uploadOffset  ?? this.uploadOffset;
    e.uploadId      = uploadId      ?? this.uploadId;
    return e;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoSegmentoEntity && other.clientId == clientId;

  @override
  int get hashCode => clientId.hashCode;

  @override
  String toString() =>
      'VideoSegmentoEntity(clientId: $clientId, id: $id, segmentoId: $segmentoId, '
      'tipo: ${tipoVideo.etiqueta}, filename: $filename, offset: $uploadOffset)';
}
