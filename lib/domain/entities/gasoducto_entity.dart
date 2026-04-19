import 'package:latlong2/latlong.dart';

class GasoductoEntity {
  final String id;
  final String nombre;

  /// CT al que pertenece este gasoducto.
  final int ctId;
  final List<LatLng> points;
  final int colorValue;
  final double strokeWidth;

  GasoductoEntity({
    required this.id,
    required this.nombre,
    required this.ctId,
    required this.points,
    this.colorValue = 0xFF1565C0,
    this.strokeWidth = 3.0,
  });

  static List<GasoductoEntity> fromGeoJson(
    Map<String, dynamic> json,
    int ctId,
  ) {
    final features = json['features'] as List? ?? [];
    final result = <GasoductoEntity>[];

    for (final feature in features) {
      try {
        final f = feature as Map<String, dynamic>;
        final geometry = f['geometry'] as Map<String, dynamic>?;
        if (geometry == null) continue;

        final type = geometry['type'] as String?;
        final properties = f['properties'] as Map<String, dynamic>? ?? {};

        final String nombre =
            (properties['name'] ?? properties['nombre'] ?? '$ctId').toString();
        final String id = (properties['id'] ??
                properties['gasoducto_id'] ??
                '${ctId}_${result.length}')
            .toString();
        final int colorVal =
            (properties['color_value'] as num?)?.toInt() ?? 0xFF1565C0;
        final double width =
            (properties['stroke_width'] as num?)?.toDouble() ?? 3.0;

        if (type == 'LineString') {
          final coords = geometry['coordinates'] as List? ?? [];
          final points = _parseCoords(coords);
          if (points.isNotEmpty) {
            result.add(GasoductoEntity(
              id: id,
              nombre: nombre,
              ctId: ctId,
              points: points,
              colorValue: colorVal,
              strokeWidth: width,
            ));
          }
        } else if (type == 'MultiLineString') {
          final lines = geometry['coordinates'] as List? ?? [];
          for (int i = 0; i < lines.length; i++) {
            final points = _parseCoords(lines[i] as List);
            if (points.isNotEmpty) {
              result.add(GasoductoEntity(
                id: '${id}_$i',
                nombre: nombre,
                ctId: ctId,
                points: points,
                colorValue: colorVal,
                strokeWidth: width,
              ));
            }
          }
        }
      } catch (_) {
        continue;
      }
    }
    return result;
  }

  static List<LatLng> _parseCoords(List<dynamic> coords) {
    final result = <LatLng>[];
    for (final c in coords) {
      try {
        final pair = c as List;
        final lng = (pair[0] as num).toDouble();
        final lat = (pair[1] as num).toDouble();
        if (lat.abs() <= 90 && lng.abs() <= 180) {
          result.add(LatLng(lat, lng));
        }
      } catch (_) {
        continue;
      }
    }
    return result;
  }
}
