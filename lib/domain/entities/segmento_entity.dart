import 'dart:convert';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'actividad_entity.dart';

enum TipoInstalacion {
  concentrada,
  lineal;

  static TipoInstalacion fromString(String? s) =>
    s?.toLowerCase() == 'concentrada'
      ? TipoInstalacion.concentrada
      : TipoInstalacion.lineal;
}

class SegmentoEntity {
  final int? id;
  final int ctId;
  final int actividadId;
  final String? nombre;
  final String? descripcion;
  final String? traza;
  final TipoInstalacion tipoInstalacion;
  final TipoActividad tipoActividad;
  EstadoActividad estado;
  final double? pkInicio;
  final double? pkFin;
  final double? latInicio;
  final double? lngInicio;
  final double? latFin;
  final double? lngFin;
  final List<LatLng> ubicacionGis;

  SegmentoEntity({
    this.id,
    required this.ctId,
    required this.actividadId,
    this.nombre,
    this.descripcion,
    this.traza,
    required this.tipoInstalacion,
    required this.tipoActividad,
    required this.estado,
    this.pkInicio,
    this.pkFin,
    this.latInicio,
    this.lngInicio,
    this.latFin,
    this.lngFin,
    required this.ubicacionGis,
  });

  double get longitud {
    if (ubicacionGis.length < 2) return 0.0;
    double total = 0.0;
    for (int i = 0; i < ubicacionGis.length - 1; i++) {
      total += _haversine(ubicacionGis[i], ubicacionGis[i + 1]);
    }
    return total;
  }

  double get superficie {
    final sup = longitud * 4;
    return sup;
  }  

  double get longitudKm => longitud / 1000;

  String get displayName =>
    [nombre, traza].where((s) => s != null && s.isNotEmpty).join(' - ');

  Map<String, dynamic> get ubicacionGisAsGeoJSON => {
    'type': 'LineString',
    'coordinates': ubicacionGis.map((p) => [p.longitude, p.latitude]).toList(),
  };

  double _haversine(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final h = sin(dLat / 2) * sin(dLat / 2) +
              cos(_deg2rad(a.latitude)) * cos(_deg2rad(b.latitude)) *
              sin(dLon / 2) * sin(dLon / 2);
    return 2 * R * asin(sqrt(h));
  }

  double _deg2rad(double deg) => deg * pi / 180;

  factory SegmentoEntity.fromJson(Map<String, dynamic> json) {
    List<LatLng> gis = [];
    final gisRaw = json['ubicacion_gis'];
    if (gisRaw != null) {
      try {
        Map<String, dynamic> geoJson;
        if (gisRaw is String) {
          geoJson = jsonDecode(gisRaw) as Map<String, dynamic>;
        } else {
          geoJson = gisRaw as Map<String, dynamic>;
        }
        final coords = geoJson['coordinates'] as List?;
        if (coords != null) {
          // GeoJSON usa [lng, lat] → invertir a LatLng(lat, lng)
          gis = coords.map((c) {
            final pair = c as List;
            return LatLng(
              (pair[1] as num).toDouble(),
              (pair[0] as num).toDouble(),
            );
          }).toList();
        }
      } catch (_) {}
    }
    return SegmentoEntity(
      id: json['id'] as int?,
      ctId: json['ct_id'] as int? ?? 0,
      actividadId: json['actividad_id'] as int? ?? 0,
      nombre: json['nombre'] as String?,
      descripcion: json['descripcion'] as String?,
      traza: json['traza'] as String?,
      tipoInstalacion: TipoInstalacion.fromString(json['tipo_instalacion'] as String?),
      tipoActividad: TipoActividad.fromString(json['tipo_actividad'] as String?),
      estado: EstadoActividad.fromString(json['estado'] as String?),
      pkInicio: (json['pk_inicio'] as num?)?.toDouble(),
      pkFin: (json['pk_fin'] as num?)?.toDouble(),
      latInicio: (json['lat_inicio'] as num?)?.toDouble(),
      lngInicio: (json['lng_inicio'] as num?)?.toDouble(),
      latFin: (json['lat_fin'] as num?)?.toDouble(),
      lngFin: (json['lng_fin'] as num?)?.toDouble(),
      ubicacionGis: gis,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ct_id': ctId,
    'actividad_id': actividadId,
    'nombre': nombre,
    'descripcion': descripcion,
    'traza': traza,
    'tipo_instalacion': tipoInstalacion.name,
    'tipo_actividad': tipoActividad.descripcion,
    'estado': estado.descripcion,
    'pk_inicio': pkInicio,
    'pk_fin': pkFin,
    'lat_inicio': latInicio,
    'lng_inicio': lngInicio,
    'lat_fin': latFin,
    'lng_fin': lngFin,
    'ubicacion_gis': jsonEncode(ubicacionGisAsGeoJSON),
  };
}
