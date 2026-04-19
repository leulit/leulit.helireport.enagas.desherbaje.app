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

/// Nombres de campos mapeados a la tabla `imagenes_segmento`
enum ImagenSegmentoFieldNames {
  id('id'),
  actividadId('actividad_id'),
  segmentoId('segmento_id'),
  tipoFoto('tipo_foto'),
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
  updatedAt('updated_at');

  final String value;
  const ImagenSegmentoFieldNames(this.value);
}

/// Entidad que representa una imagen de la tabla `imagenes_segmento`
class ImagenSegmentoEntity implements Syncable {
  ImagenSegmentoEntity({
    required this.actividadId,
    required this.segmentoId,
    required this.tipoFoto,
    required this.filename,
    required this.ruta,
    required this.capturadaAt,
  });

  int? id;
  int actividadId;
  int segmentoId;
  TipoFoto tipoFoto;
  String filename;
  String ruta;
  String? url;
  String mimeType = 'image/jpeg';
  int? tamanyoBytes;
  double? latitud;
  double? longitud;
  double? fixedLatitud;
  double? fixedLongitud;
  DateTime capturadaAt;
  DateTime? subidaAt;
  int? subidaPor;
  DateTime? createdAt;
  @override
  DateTime? updatedAt;

  /// Devuelve true si la imagen ya ha sido subida al servidor
  bool get isSubida => subidaAt != null;

  /// Devuelve true si es una foto de tipo "antes"
  bool get isAntes => tipoFoto == TipoFoto.antes;

  /// Devuelve true si es una foto de tipo "después"
  bool get isDespues => tipoFoto == TipoFoto.despues;

  /// Tamaño legible (e.g. "1.2 MB")
  String get tamanyoLegible {
    final bytes = tamanyoBytes;
    if (bytes == null) return 'Desconocido';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

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
      actividadId: readJsonDataUtil<int>(json, ImagenSegmentoFieldNames.actividadId.value, 0),
      segmentoId:  readJsonDataUtil<int>(json, ImagenSegmentoFieldNames.segmentoId.value, 0),
      tipoFoto:    TipoFoto.fromString(readJsonDataUtil<String?>(json, ImagenSegmentoFieldNames.tipoFoto.value, null)),
      filename:    readJsonDataUtil<String>(json, ImagenSegmentoFieldNames.filename.value, ''),
      ruta:        readJsonDataUtil<String>(json, ImagenSegmentoFieldNames.ruta.value, ''),
      capturadaAt: parseDate(ImagenSegmentoFieldNames.capturadaAt.value, DateTime.now()),
    );

    entity.id           = readJsonDataUtil<int?>(json, ImagenSegmentoFieldNames.id.value, null);
    entity.url          = readJsonDataUtil<String?>(json, ImagenSegmentoFieldNames.url.value, null);
    entity.mimeType     = readJsonDataUtil<String>(json, ImagenSegmentoFieldNames.mimeType.value, 'image/jpeg');
    entity.tamanyoBytes = readJsonDataUtil<int?>(json, ImagenSegmentoFieldNames.tamanyoBytes.value, null);
    entity.latitud       = (readJsonDataUtil<num?>(json, ImagenSegmentoFieldNames.latitud.value, null))?.toDouble();
    entity.longitud      = (readJsonDataUtil<num?>(json, ImagenSegmentoFieldNames.longitud.value, null))?.toDouble();
    entity.fixedLatitud  = (readJsonDataUtil<num?>(json, ImagenSegmentoFieldNames.fixedLatitud.value, null))?.toDouble();
    entity.fixedLongitud = (readJsonDataUtil<num?>(json, ImagenSegmentoFieldNames.fixedLongitud.value, null))?.toDouble();
    entity.subidaPor     = readJsonDataUtil<int?>(json, ImagenSegmentoFieldNames.subidaPor.value, null);

    try {
      final subidaRaw = json[ImagenSegmentoFieldNames.subidaAt.value];
      if (subidaRaw != null) entity.subidaAt = DateTime.parse(subidaRaw.toString());
    } catch (_) {}

    try {
      final createdRaw = json[ImagenSegmentoFieldNames.createdAt.value];
      if (createdRaw != null) entity.createdAt = DateTime.parse(createdRaw.toString());
    } catch (_) {}

    try {
      final updatedRaw = json[ImagenSegmentoFieldNames.updatedAt.value];
      if (updatedRaw != null) entity.updatedAt = DateTime.parse(updatedRaw.toString());
    } catch (_) {}

    return entity;
  }

  @override
  Map<String, dynamic> toJson() => {
    ImagenSegmentoFieldNames.id.value:           id,
    ImagenSegmentoFieldNames.actividadId.value:  actividadId,
    ImagenSegmentoFieldNames.segmentoId.value:   segmentoId,
    ImagenSegmentoFieldNames.tipoFoto.value:     tipoFoto.valor,
    ImagenSegmentoFieldNames.filename.value:     filename,
    ImagenSegmentoFieldNames.ruta.value:         ruta,
    ImagenSegmentoFieldNames.url.value:          url,
    ImagenSegmentoFieldNames.mimeType.value:     mimeType,
    ImagenSegmentoFieldNames.tamanyoBytes.value: tamanyoBytes,
    ImagenSegmentoFieldNames.latitud.value:       latitud,
    ImagenSegmentoFieldNames.longitud.value:      longitud,
    ImagenSegmentoFieldNames.fixedLatitud.value:  fixedLatitud,
    ImagenSegmentoFieldNames.fixedLongitud.value: fixedLongitud,
    ImagenSegmentoFieldNames.capturadaAt.value:   capturadaAt.toIso8601String(),
    ImagenSegmentoFieldNames.subidaAt.value:     subidaAt?.toIso8601String(),
    ImagenSegmentoFieldNames.subidaPor.value:    subidaPor,
  };

  ImagenSegmentoEntity copyWith({
    int? id,
    int? actividadId,
    int? segmentoId,
    TipoFoto? tipoFoto,
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
  }) {
    final e = ImagenSegmentoEntity(
      actividadId: actividadId ?? this.actividadId,
      segmentoId:  segmentoId  ?? this.segmentoId,
      tipoFoto:    tipoFoto    ?? this.tipoFoto,
      filename:    filename    ?? this.filename,
      ruta:        ruta        ?? this.ruta,
      capturadaAt: capturadaAt ?? this.capturadaAt,
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
    e.subidaPor    = subidaPor    ?? this.subidaPor;
    return e;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImagenSegmentoEntity && other.id == id && other.filename == filename;

  @override
  int get hashCode => id.hashCode ^ filename.hashCode;

  @override
  String toString() =>
      'ImagenSegmentoEntity(id: $id, segmentoId: $segmentoId, tipo: ${tipoFoto.etiqueta}, filename: $filename)';
      
  @override
  // TODO: implement clientId
  String get clientId => throw UnimplementedError();

  @override
  // TODO: implement remoteId
  String? get remoteId => throw UnimplementedError();
}

