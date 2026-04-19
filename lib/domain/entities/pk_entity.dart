import 'package:latlong2/latlong.dart';

/// Punto kilométrico (PK) sobre la traza de un gasoducto. Cada feature de
/// `*-pk.json` se mapea a una instancia de [PkEntity].
class PkEntity {
  /// Identificador único (típicamente derivado de `properties.id` o
  /// `${ctId}_${index}` si el feature no trae id).
  final String id;

  /// CT al que pertenece el punto.
  final int ctId;

  /// Etiqueta del PK (ej. `"PK 12.5"`, `"12+500"`, etc.). Lo que se mostrará
  /// dentro del marcador en el mapa.
  final String label;

  /// Posición geográfica.
  final LatLng point;

  const PkEntity({
    required this.id,
    required this.ctId,
    required this.label,
    required this.point,
  });

  /// Parsea un GeoJSON `FeatureCollection` con geometrías `Point` y
  /// devuelve la lista de PKs. Tolerante con propiedades faltantes:
  ///
  /// - `properties.pk` o `properties.label` o `properties.name` → [label].
  /// - `properties.id` o `properties.pk_id` → [id]; si no, `${ctId}_${i}`.
  static List<PkEntity> fromGeoJson(Map<String, dynamic> json, int ctId) {
    final features = json['features'] as List? ?? const [];
    final result = <PkEntity>[];

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

        final rawLabel = properties['pk'] ??
            properties['label'] ??
            properties['name'] ??
            properties['nombre'];
        final label = rawLabel != null ? rawLabel.toString() : '';

        final rawId = properties['id'] ?? properties['pk_id'];
        final id = rawId != null
            ? rawId.toString()
            : '${ctId}_${result.length}';

        result.add(PkEntity(
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
