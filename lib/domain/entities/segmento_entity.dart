import 'dart:convert';
import 'package:latlong2/latlong.dart';

import '../../core/sync/contracts/syncable.dart';
import '../../data/model/base_model.dart';
import '../../data/model/json_parsing_utils.dart';
import '../../data/model/mensaje_entity.dart';
import 'imagen_segmento_entity.dart';

/// Define el tipo de instalación según la tabla `inventario_segmentos`.
enum TipoInstalacion {
  concentrada,
  lineal;

  static TipoInstalacion fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'concentrada':
        return TipoInstalacion.concentrada;
      case 'lineal':
      default:
        return TipoInstalacion.lineal;
    }
  }

  String get asString => name;
}

/// Tipo de actividad de desherbaje asociado al segmento.
enum TipoActividad {
  desbroceManual('desbroce_manual', 'Desbroce Manual'),
  desbroceMecanico('desbroce_mecanico', 'Desbroce Mecánico'),
  deshierbePosiciones('deshierbe_posiciones', 'Deshierbe Posiciones'),
  desherbajeSelectivo('deshierbe_selectivo', 'Deshierbe Selectivo'),
  desratizacion('desratizacion', 'Desratización'),
  resiembre('resiembre', 'Resiembre'),
  talaArboles('tala_arboles', 'Tala de Árboles');

  final String descripcion;
  final String etiqueta;
  const TipoActividad(this.descripcion, this.etiqueta);

  static TipoActividad fromString(String? value) {
    if (value == null) return TipoActividad.desherbajeSelectivo;
    // Compatibilidad con el valor legacy antes del cambio a "deshierbe_*":
    // filas existentes en SQLite o respuestas antiguas del backend que
    // todavía lleven "desherbaje_selectivo" deben mapear al mismo caso.
    if (value == 'desherbaje_selectivo') return TipoActividad.desherbajeSelectivo;
    return TipoActividad.values.firstWhere(
      (e) => e.descripcion == value,
      orElse: () => TipoActividad.desherbajeSelectivo,
    );
  }
}

/// Estado del segmento (antes era el estado de la actividad).
enum EstadoActividad {
  propuesta('propuesta', 'Propuesta'),
  contratista('contratista', 'Contratista'),
  validada('validada', 'Validada'),
  ejecucion('ejecución', 'En Ejecución'),
  finalizada('finalizada', 'Finalizada'),
  cerrada('cerrada', 'Cerrada');

  final String descripcion;
  final String etiqueta;
  const EstadoActividad(this.descripcion, this.etiqueta);

  static EstadoActividad fromString(String? value) {
    if (value == null) return EstadoActividad.propuesta;
    final q = _normalize(value);
    return EstadoActividad.values.firstWhere(
      (e) => _normalize(e.descripcion) == q || _normalize(e.name) == q,
      orElse: () => EstadoActividad.propuesta,
    );
  }

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[áàäâ]'), 'a')
      .replaceAll(RegExp(r'[éèëê]'), 'e')
      .replaceAll(RegExp(r'[íìïî]'), 'i')
      .replaceAll(RegExp(r'[óòöô]'), 'o')
      .replaceAll(RegExp(r'[úùüû]'), 'u');
}

enum SegmentoEntityFieldNames {
  id('id'),
  ctId('ct_id'),
  nombre('nombre'),
  descripcion('descripcion'),
  traza('traza'),
  tipoInstalacion('tipo_instalacion'),
  pkInicio('pk_inicio'),
  pkFin('pk_fin'),
  latInicio('lat_inicio'),
  lngInicio('lng_inicio'),
  latFin('lat_fin'),
  lngFin('lng_fin'),
  ubicacionGis('ubicacion_gis'),
  tipoActividad('tipo_actividad'),
  imagenes('imagenes'),
  mensajes('mensajes'),
  estado('estado'),
  createdAt('created_at'),
  fechaInicio('fecha_inico'),
  fechaFin('fecha_fin');

  final String value;
  const SegmentoEntityFieldNames(this.value);
}

/// Entidad que representa un segmento de inventario (`inventario_segmentos`).
///
/// Absorbe los campos que antes vivían en `ActividadEntity` (`estado`,
/// `tipoActividad`, `fechaInicio`, `fechaFin`, etc.). No hay un concepto
/// separado de "actividad" en el dominio de la app.
class SegmentoEntity extends AbsBaseModel
    with BaseModelMixin
    implements Syncable {
  SegmentoEntity(
    this.id,
    this.ctId,
    this.tipoInstalacion,
    this.ubicacionGis,
  );

  SegmentoEntity.empty() {
    id = null;
    ctId = 0;
    tipoInstalacion = TipoInstalacion.lineal;
    ubicacionGis = [];
    nombre = null;
    descripcion = '';
    traza = null;
    tipoActividad = TipoActividad.desherbajeSelectivo;
    estado = EstadoActividad.propuesta;
    imagenes = [];
    mensajes = [];
    createdAt = null;
    fechaInicio = null;
    fechaFin = null;
  }

  int? id;
  int ctId = 0;
  String? nombre;
  String descripcion = '';
  String? traza;
  TipoInstalacion tipoInstalacion = TipoInstalacion.lineal;
  double? pkInicio;
  double? pkFin;
  double? latInicio;
  double? lngInicio;
  double? latFin;
  double? lngFin;
  List<LatLng> ubicacionGis = [];
  TipoActividad tipoActividad = TipoActividad.desherbajeSelectivo;
  EstadoActividad estado = EstadoActividad.propuesta;
  List<ImagenSegmentoEntity> imagenes = [];
  List<MensajeSegmentoEntity> mensajes = [];
  DateTime? createdAt;
  DateTime? fechaInicio;
  DateTime? fechaFin;

  factory SegmentoEntity.fromJson(Map<String, dynamic> json) {
    final id = readJsonDataUtil<int?>(
      json,
      SegmentoEntityFieldNames.id.value,
      null,
    );
    final ctId = readJsonDataUtil<int>(
      json,
      SegmentoEntityFieldNames.ctId.value,
      0,
    );
    final tipoInstalacion = TipoInstalacion.fromString(
      readJsonDataUtil<String?>(
        json,
        SegmentoEntityFieldNames.tipoInstalacion.value,
        'lineal',
      ),
    );

    List<LatLng> parsedUbicacion = [];
    final ubicacionRaw = json[SegmentoEntityFieldNames.ubicacionGis.value];
    if (ubicacionRaw != null) {
      try {
        final ubicacionJson =
            ubicacionRaw is String ? jsonDecode(ubicacionRaw) : ubicacionRaw;
        if (ubicacionJson is Map<String, dynamic> &&
            ubicacionJson['type'] == 'LineString' &&
            ubicacionJson['coordinates'] is List) {
          final coords = ubicacionJson['coordinates'] as List;
          parsedUbicacion = coords
              .whereType<List>()
              .map(
                (c) => LatLng(
                  (c[1] as num).toDouble(),
                  (c[0] as num).toDouble(),
                ),
              )
              .toList();
        }
      } catch (_) {}
    }

    final entity = SegmentoEntity(id, ctId, tipoInstalacion, parsedUbicacion);

    entity.nombre = readJsonDataUtil<String?>(
      json,
      SegmentoEntityFieldNames.nombre.value,
      null,
    );
    entity.traza = readJsonDataUtil<String?>(
      json,
      SegmentoEntityFieldNames.traza.value,
      null,
    );
    entity.descripcion = readJsonDataUtil<String>(
      json,
      SegmentoEntityFieldNames.descripcion.value,
      '',
    );

    entity.pkInicio = (readJsonDataUtil<num?>(
      json,
      SegmentoEntityFieldNames.pkInicio.value,
      null,
    ))?.toDouble();
    entity.pkFin = (readJsonDataUtil<num?>(
      json,
      SegmentoEntityFieldNames.pkFin.value,
      null,
    ))?.toDouble();
    entity.latInicio = (readJsonDataUtil<num?>(
      json,
      SegmentoEntityFieldNames.latInicio.value,
      null,
    ))?.toDouble();
    entity.lngInicio = (readJsonDataUtil<num?>(
      json,
      SegmentoEntityFieldNames.lngInicio.value,
      null,
    ))?.toDouble();
    entity.latFin = (readJsonDataUtil<num?>(
      json,
      SegmentoEntityFieldNames.latFin.value,
      null,
    ))?.toDouble();
    entity.lngFin = (readJsonDataUtil<num?>(
      json,
      SegmentoEntityFieldNames.lngFin.value,
      null,
    ))?.toDouble();

    entity.tipoActividad = TipoActividad.fromString(
      readJsonDataUtil<String>(
        json,
        SegmentoEntityFieldNames.tipoActividad.value,
        'desherbaje_selectivo',
      ),
    );
    entity.estado = EstadoActividad.fromString(
      readJsonDataUtil<String>(
        json,
        SegmentoEntityFieldNames.estado.value,
        'propuesta',
      ),
    );

    final imagenesRaw = json[SegmentoEntityFieldNames.imagenes.value];
    if (imagenesRaw is List) {
      entity.imagenes = imagenesRaw
          .whereType<Map<String, dynamic>>()
          .map(ImagenSegmentoEntity.fromJson)
          .toList();
    }

    final mensajesRaw = json[SegmentoEntityFieldNames.mensajes.value];
    if (mensajesRaw is List) {
      entity.mensajes = mensajesRaw
          .whereType<Map<String, dynamic>>()
          .map(MensajeSegmentoEntity.fromJson)
          .toList();
    }

    final createdAtRaw = readJsonDataUtil<String?>(
      json,
      SegmentoEntityFieldNames.createdAt.value,
      null,
    );
    entity.createdAt =
        createdAtRaw != null ? DateTime.tryParse(createdAtRaw) : null;

    final fechaInicioRaw = readJsonDataUtil<String?>(
      json,
      SegmentoEntityFieldNames.fechaInicio.value,
      null,
    );
    entity.fechaInicio =
        fechaInicioRaw != null ? DateTime.tryParse(fechaInicioRaw) : null;

    final fechaFinRaw = readJsonDataUtil<String?>(
      json,
      SegmentoEntityFieldNames.fechaFin.value,
      null,
    );
    entity.fechaFin =
        fechaFinRaw != null ? DateTime.tryParse(fechaFinRaw) : null;

    return entity;
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      SegmentoEntityFieldNames.id.value: id,
      SegmentoEntityFieldNames.ctId.value: ctId,
      SegmentoEntityFieldNames.nombre.value: nombre,
      SegmentoEntityFieldNames.descripcion.value: descripcion,
      SegmentoEntityFieldNames.traza.value: traza,
      SegmentoEntityFieldNames.tipoInstalacion.value: tipoInstalacion.asString,
      SegmentoEntityFieldNames.pkInicio.value: pkInicio,
      SegmentoEntityFieldNames.pkFin.value: pkFin,
      SegmentoEntityFieldNames.latInicio.value: latInicio,
      SegmentoEntityFieldNames.lngInicio.value: lngInicio,
      SegmentoEntityFieldNames.latFin.value: latFin,
      SegmentoEntityFieldNames.lngFin.value: lngFin,
      SegmentoEntityFieldNames.ubicacionGis.value: ubicacionGisAsGeoJSON,
      SegmentoEntityFieldNames.tipoActividad.value: tipoActividad.descripcion,
      SegmentoEntityFieldNames.estado.value: estado.descripcion,
      SegmentoEntityFieldNames.imagenes.value:
          imagenes.map((e) => e.toJson()).toList(),
      SegmentoEntityFieldNames.mensajes.value:
          mensajes.map((e) => e.toJson()).toList(),
      SegmentoEntityFieldNames.createdAt.value: createdAt?.toIso8601String(),
      SegmentoEntityFieldNames.fechaInicio.value:
          fechaInicio?.toIso8601String(),
      SegmentoEntityFieldNames.fechaFin.value: fechaFin?.toIso8601String(),
    };
  }

  // ──────────────────────────── Syncable ────────────────────────────

  @override
  String get clientId => 'seg-${id ?? 0}';

  @override
  String? get remoteId => id?.toString();

  @override
  DateTime get updatedAt =>
      fechaFin ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  // ──────────────────────────── Derived ────────────────────────────

  String get displayName => [
        nombre,
        traza,
      ].where((s) => s != null && s.isNotEmpty).join(' - ');

  /// Longitud del segmento en metros calculada con Haversine sobre la traza GIS.
  double get longitud {
    if (ubicacionGis.length < 2) return 0.0;
    const distance = Distance();
    double total = 0.0;
    for (int i = 0; i < ubicacionGis.length - 1; i++) {
      total +=
          distance.as(LengthUnit.Meter, ubicacionGis[i], ubicacionGis[i + 1]);
    }
    return total;
  }

  double get longitudKm => longitud / 1000;

  /// Superficie estimada en m² (ancho de traza fijo de 4 m).
  double get superficie => longitud * 4;

  Map<String, dynamic> get ubicacionGisAsGeoJSON => {
        'type': 'LineString',
        'coordinates':
            ubicacionGis.map((p) => [p.longitude, p.latitude]).toList(),
      };

  /// Etiqueta del tipo de actividad (compatibilidad con callers previos).
  String get tipoLabel => tipoActividad.etiqueta;

  SegmentoEntity copyWith({
    int? id,
    int? ctId,
    String? nombre,
    String? descripcion,
    String? traza,
    TipoInstalacion? tipoInstalacion,
    double? pkInicio,
    double? pkFin,
    double? latInicio,
    double? lngInicio,
    double? latFin,
    double? lngFin,
    List<LatLng>? ubicacionGis,
    TipoActividad? tipoActividad,
    EstadoActividad? estado,
    List<ImagenSegmentoEntity>? imagenes,
    List<MensajeSegmentoEntity>? mensajes,
    DateTime? createdAt,
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) {
    final copy = SegmentoEntity(
      id ?? this.id,
      ctId ?? this.ctId,
      tipoInstalacion ?? this.tipoInstalacion,
      ubicacionGis ?? List<LatLng>.from(this.ubicacionGis),
    );
    copy.nombre = nombre ?? this.nombre;
    copy.descripcion = descripcion ?? this.descripcion;
    copy.traza = traza ?? this.traza;
    copy.pkInicio = pkInicio ?? this.pkInicio;
    copy.pkFin = pkFin ?? this.pkFin;
    copy.latInicio = latInicio ?? this.latInicio;
    copy.lngInicio = lngInicio ?? this.lngInicio;
    copy.latFin = latFin ?? this.latFin;
    copy.lngFin = lngFin ?? this.lngFin;
    copy.tipoActividad = tipoActividad ?? this.tipoActividad;
    copy.estado = estado ?? this.estado;
    copy.imagenes =
        imagenes ?? List<ImagenSegmentoEntity>.from(this.imagenes);
    copy.mensajes = mensajes ?? List<MensajeSegmentoEntity>.from(this.mensajes);
    copy.createdAt = createdAt ?? this.createdAt;
    copy.fechaInicio = fechaInicio ?? this.fechaInicio;
    copy.fechaFin = fechaFin ?? this.fechaFin;
    return copy;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SegmentoEntity &&
          other.id == id &&
          other.ctId == ctId &&
          other.nombre == nombre &&
          other.traza == traza);

  @override
  int get hashCode =>
      id.hashCode ^ ctId.hashCode ^ nombre.hashCode ^ traza.hashCode;

  @override
  String toString() =>
      'SegmentoEntity(id: $id, ctId: $ctId, nombre: $nombre, '
      'estado: ${estado.descripcion}, longitud: ${longitudKm.toStringAsFixed(2)}km)';
}
