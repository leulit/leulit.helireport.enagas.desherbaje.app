import 'package:uuid/uuid.dart';

import '../../core/sync/contracts/syncable.dart';
import '../../data/model/json_parsing_utils.dart';

/// Tipo de foto: antes o después del trabajo
enum TipoFoto {
  antes('antes', 'Antes'),
  despues('despues', 'Después');

  final String valor;
  final String etiqueta;

  const TipoFoto(this.valor, this.etiqueta);

  static TipoFoto fromString(String? value) {
    return TipoFoto.values.firstWhere(
      (e) => e.valor == value,
      orElse: () => TipoFoto.antes,
    );
  }
}

/// Nombres de campos mapeados a la tabla `imagenes_segmento` (backend + cache).
enum ImagenSegmentoFieldNames {
  id('id'),
  clientId('client_id'),
  actividadId('actividad_id'),
  segmentoId('segmento_id'),
  segmentoClientId('segmento_client_id'),
  tipoFoto('tipo_foto'),
  filename('filename'),
  ruta('ruta'),
  url('url'),
  mimeType('mime_type'),
  tamanyoBytes('tamanyo_bytes'),
  gisJson('gis_json'),
  capturadaAt('capturada_at'),
  subidaAt('subida_at'),
  subidaPor('subida_por'),
  createdAt('created_at'),
  updatedAt('updated_at'),
  syncedAt('synced_at'),
  needsSync('needs_sync');

  final String value;
  const ImagenSegmentoFieldNames(this.value);
}

/// Entidad que representa una imagen capturada en campo. Mapea 1:1 contra la
/// tabla local `imagenes_segmento` y contra el endpoint del backend.
class ImagenSegmentoEntity implements Syncable {
  ImagenSegmentoEntity({
    required this.actividadId,
    required this.segmentoId,
    required this.tipoFoto,
    required this.filename,
    required this.ruta,
    required this.capturadaAt,
    String? clientId,
    this.segmentoClientId,
  }) : _clientId = clientId ?? const Uuid().v4();

  /// Identificador remoto asignado por el backend tras la subida.
  int? id;

  /// Identificador estable generado en cliente. Persistido en `client_id`
  /// para que el outbox sea idempotente cuando aún no existe `id` remoto.
  final String _clientId;

  int actividadId;
  int segmentoId;

  /// `clientId` (UUID local) del segmento propietario de esta captura. Es el
  /// vínculo estable local: `segmentoId` (remoto) vale 0 mientras el
  /// segmento no ha sincronizado, así que las lecturas locales deben filtrar
  /// por este campo, no por `segmentoId`.
  String? segmentoClientId;
  TipoFoto tipoFoto;
  String filename;

  /// Ruta del fichero. Local mientras `subidaAt == null`; ruta servidor tras
  /// la subida.
  String ruta;
  String? url;
  String mimeType = 'image/jpeg';
  int? tamanyoBytes;

  /// GeoJSON FeatureCollection con la geolocalización de la captura (posición,
  /// rumbo y metadatos de dispositivo). Null si la captura se hizo sin GPS.
  String? gisJson;
  DateTime capturadaAt;
  DateTime? subidaAt;
  int? subidaPor;
  DateTime? createdAt;
  DateTime? updatedAtRemote;

  bool get isSubida => subidaAt != null;
  bool get isAntes => tipoFoto == TipoFoto.antes;
  bool get isDespues => tipoFoto == TipoFoto.despues;

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

  @override
  String? get remoteId => id?.toString();

  @override
  DateTime get updatedAt => updatedAtRemote ?? subidaAt ?? capturadaAt;

  // ──────────────────────────── JSON (backend) ────────────────────────────

  factory ImagenSegmentoEntity.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String field, DateTime fallback) {
      try {
        final raw = json[field];
        if (raw == null) return fallback;
        return DateTime.parse(raw.toString());
      } catch (_) {
        return fallback;
      }
    }

    final entity = ImagenSegmentoEntity(
      actividadId: readJsonDataUtil<int>(
          json, ImagenSegmentoFieldNames.actividadId.value, 0),
      segmentoId: readJsonDataUtil<int>(
          json, ImagenSegmentoFieldNames.segmentoId.value, 0),
      tipoFoto: TipoFoto.fromString(readJsonDataUtil<String?>(
          json, ImagenSegmentoFieldNames.tipoFoto.value, null)),
      filename: readJsonDataUtil<String>(
          json, ImagenSegmentoFieldNames.filename.value, ''),
      ruta: readJsonDataUtil<String>(
          json, ImagenSegmentoFieldNames.ruta.value, ''),
      capturadaAt:
          parseDate(ImagenSegmentoFieldNames.capturadaAt.value, DateTime.now()),
      clientId: readJsonDataUtil<String?>(
          json, ImagenSegmentoFieldNames.clientId.value, null),
    );

    entity.id =
        readJsonDataUtil<int?>(json, ImagenSegmentoFieldNames.id.value, null);
    entity.url = readJsonDataUtil<String?>(
        json, ImagenSegmentoFieldNames.url.value, null);
    entity.mimeType = readJsonDataUtil<String>(
        json, ImagenSegmentoFieldNames.mimeType.value, 'image/jpeg');
    entity.tamanyoBytes = readJsonDataUtil<int?>(
        json, ImagenSegmentoFieldNames.tamanyoBytes.value, null);
    entity.gisJson = readJsonDataUtil<String?>(
        json, ImagenSegmentoFieldNames.gisJson.value, null);
    entity.subidaPor = readJsonDataUtil<int?>(
        json, ImagenSegmentoFieldNames.subidaPor.value, null);

    try {
      final subidaRaw = json[ImagenSegmentoFieldNames.subidaAt.value];
      if (subidaRaw != null) {
        entity.subidaAt = DateTime.parse(subidaRaw.toString());
      }
    } catch (_) {}

    try {
      final createdRaw = json[ImagenSegmentoFieldNames.createdAt.value];
      if (createdRaw != null) {
        entity.createdAt = DateTime.parse(createdRaw.toString());
      }
    } catch (_) {}

    try {
      final updatedRaw = json[ImagenSegmentoFieldNames.updatedAt.value];
      if (updatedRaw != null) {
        entity.updatedAtRemote = DateTime.parse(updatedRaw.toString());
      }
    } catch (_) {}

    return entity;
  }

  @override
  Map<String, dynamic> toJson() => {
        ImagenSegmentoFieldNames.id.value: id,
        ImagenSegmentoFieldNames.clientId.value: clientId,
        ImagenSegmentoFieldNames.actividadId.value: actividadId,
        ImagenSegmentoFieldNames.segmentoId.value: segmentoId,
        ImagenSegmentoFieldNames.tipoFoto.value: tipoFoto.valor,
        ImagenSegmentoFieldNames.filename.value: filename,
        ImagenSegmentoFieldNames.ruta.value: ruta,
        ImagenSegmentoFieldNames.url.value: url,
        ImagenSegmentoFieldNames.mimeType.value: mimeType,
        ImagenSegmentoFieldNames.tamanyoBytes.value: tamanyoBytes,
        ImagenSegmentoFieldNames.gisJson.value: gisJson,
        ImagenSegmentoFieldNames.capturadaAt.value:
            capturadaAt.toIso8601String(),
        ImagenSegmentoFieldNames.subidaAt.value: subidaAt?.toIso8601String(),
        ImagenSegmentoFieldNames.subidaPor.value: subidaPor,
      };

  // ──────────────────────────── SQLite map ────────────────────────────

  /// Mapa para la tabla local `imagenes_segmento`. Coincide con `toJson` y
  /// añade los campos de control de sincronía (`synced_at`, `needs_sync`).
  Map<String, Object?> toMap({bool needsSync = true}) => {
        ImagenSegmentoFieldNames.id.value: id,
        ImagenSegmentoFieldNames.clientId.value: clientId,
        ImagenSegmentoFieldNames.actividadId.value: actividadId,
        ImagenSegmentoFieldNames.segmentoId.value: segmentoId,
        ImagenSegmentoFieldNames.segmentoClientId.value: segmentoClientId,
        ImagenSegmentoFieldNames.tipoFoto.value: tipoFoto.valor,
        ImagenSegmentoFieldNames.filename.value: filename,
        ImagenSegmentoFieldNames.ruta.value: ruta,
        ImagenSegmentoFieldNames.url.value: url,
        ImagenSegmentoFieldNames.mimeType.value: mimeType,
        ImagenSegmentoFieldNames.tamanyoBytes.value: tamanyoBytes,
        ImagenSegmentoFieldNames.gisJson.value: gisJson,
        ImagenSegmentoFieldNames.capturadaAt.value:
            capturadaAt.toIso8601String(),
        ImagenSegmentoFieldNames.subidaAt.value: subidaAt?.toIso8601String(),
        ImagenSegmentoFieldNames.subidaPor.value: subidaPor,
        ImagenSegmentoFieldNames.createdAt.value: createdAt?.toIso8601String(),
        ImagenSegmentoFieldNames.updatedAt.value:
            updatedAtRemote?.toIso8601String(),
        ImagenSegmentoFieldNames.needsSync.value: needsSync ? 1 : 0,
      };

  factory ImagenSegmentoEntity.fromMap(Map<String, Object?> row) {
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

    final entity = ImagenSegmentoEntity(
      actividadId:
          (row[ImagenSegmentoFieldNames.actividadId.value] as int?) ?? 0,
      segmentoId: (row[ImagenSegmentoFieldNames.segmentoId.value] as int?) ?? 0,
      tipoFoto: TipoFoto.fromString(
          row[ImagenSegmentoFieldNames.tipoFoto.value] as String?),
      filename: (row[ImagenSegmentoFieldNames.filename.value] as String?) ?? '',
      ruta: (row[ImagenSegmentoFieldNames.ruta.value] as String?) ?? '',
      capturadaAt: parseDateOr(
          ImagenSegmentoFieldNames.capturadaAt.value, DateTime.now()),
      clientId: row[ImagenSegmentoFieldNames.clientId.value] as String?,
    );

    entity.id = row[ImagenSegmentoFieldNames.id.value] as int?;
    entity.url = row[ImagenSegmentoFieldNames.url.value] as String?;
    entity.mimeType =
        (row[ImagenSegmentoFieldNames.mimeType.value] as String?) ??
            'image/jpeg';
    entity.tamanyoBytes =
        row[ImagenSegmentoFieldNames.tamanyoBytes.value] as int?;
    entity.gisJson = row[ImagenSegmentoFieldNames.gisJson.value] as String?;
    entity.subidaPor = row[ImagenSegmentoFieldNames.subidaPor.value] as int?;
    entity.subidaAt =
        parseDateNullable(ImagenSegmentoFieldNames.subidaAt.value);
    entity.createdAt =
        parseDateNullable(ImagenSegmentoFieldNames.createdAt.value);
    entity.updatedAtRemote =
        parseDateNullable(ImagenSegmentoFieldNames.updatedAt.value);
    entity.segmentoClientId =
        row[ImagenSegmentoFieldNames.segmentoClientId.value] as String?;

    return entity;
  }

  ImagenSegmentoEntity copyWith({
    int? id,
    int? actividadId,
    int? segmentoId,
    String? segmentoClientId,
    TipoFoto? tipoFoto,
    String? filename,
    String? ruta,
    String? url,
    String? mimeType,
    int? tamanyoBytes,
    String? gisJson,
    DateTime? capturadaAt,
    DateTime? subidaAt,
    int? subidaPor,
  }) {
    final e = ImagenSegmentoEntity(
      actividadId: actividadId ?? this.actividadId,
      segmentoId: segmentoId ?? this.segmentoId,
      tipoFoto: tipoFoto ?? this.tipoFoto,
      filename: filename ?? this.filename,
      ruta: ruta ?? this.ruta,
      capturadaAt: capturadaAt ?? this.capturadaAt,
      clientId: clientId,
      segmentoClientId: segmentoClientId ?? this.segmentoClientId,
    );
    e.id = id ?? this.id;
    e.url = url ?? this.url;
    e.mimeType = mimeType ?? this.mimeType;
    e.tamanyoBytes = tamanyoBytes ?? this.tamanyoBytes;
    e.gisJson = gisJson ?? this.gisJson;
    e.subidaAt = subidaAt ?? this.subidaAt;
    e.subidaPor = subidaPor ?? this.subidaPor;
    e.createdAt = createdAt;
    e.updatedAtRemote = updatedAtRemote;
    return e;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImagenSegmentoEntity && other.clientId == clientId;

  @override
  int get hashCode => clientId.hashCode;

  @override
  String toString() =>
      'ImagenSegmentoEntity(clientId: $clientId, id: $id, segmentoId: $segmentoId, '
      'tipo: ${tipoFoto.etiqueta}, filename: $filename)';
}
