import 'package:latlong2/latlong.dart';

/// Hito sobre la traza de un gasoducto. Cada feature de `*-hitos.json` se
/// mapea a una instancia de [HitoEntity]. Estructura idéntica a `PkEntity`.
class HitoEntity {
  /// Identificador único (típicamente derivado de `properties.id` o
  /// `${ctId}_${index}` si el feature no trae id).
  final String id;

  /// CT al que pertenece el hito.
  final int ctId;

  /// Etiqueta del hito. Lo que se mostrará dentro del marcador en el mapa.
  final String label;

  /// Posición geográfica.
  final LatLng point;

  const HitoEntity({
    required this.id,
    required this.ctId,
    required this.label,
    required this.point,
  });

  /// Parsea un GeoJSON `FeatureCollection` con geometrías `Point` y
  /// devuelve la lista de hitos. Tolerante con propiedades faltantes:
  ///
  /// - `properties.hito` / `label` / `name` / `nombre` / `pk` → [label].
  /// - `properties.id` / `hito_id` / `pk_id` → [id]; si no, `${ctId}_${i}`.
  static List<HitoEntity> fromGeoJson(Map<String, dynamic> json, int ctId) {
    final features = json['features'] as List? ?? const [];
    final result = <HitoEntity>[];

    for (final feature in features) {
      try {
        final f = feature as Map<String, dynamic>;
        final geometry = f['geometry'] as Map<String, dynamic>?;
        if (geometry == null) continue;

        final type = geometry['type'] as String?;
        if (type != 'Point') continue;

        final coords = geometry['coordinates'] as List?;
        if (coords == null || coords.length < 2) continue;

        final lng = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();
        if (lat.abs() > 90 || lng.abs() > 180) continue;

        final properties =
            f['properties'] as Map<String, dynamic>? ?? const {};

        final rawLabel = properties['hito'] ??
            properties['label'] ??
            properties['name'] ??
            properties['nombre'] ??
            properties['pk'];
        final label = rawLabel != null ? rawLabel.toString() : '';

        final rawId =
            properties['id'] ?? properties['hito_id'] ?? properties['pk_id'];
        final id = rawId != null
            ? rawId.toString()
            : '${ctId}_${result.length}';

        result.add(HitoEntity(
          id: id,
          ctId: ctId,
          label: label,
          point: LatLng(lat, lng),
        ));
      } catch (_) {
        continue;
      }
    }
    return result;
  }
}
