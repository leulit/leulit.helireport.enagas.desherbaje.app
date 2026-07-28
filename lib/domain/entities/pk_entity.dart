import 'dart:convert';

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

/// Estructura plana (solo primitivas) que traslada el resultado del parseo
/// GeoJSON entre isolates con el menor coste de copia posible: `lat`/`lng`
/// sueltos en vez de `LatLng`. El `LatLng`/`PkEntity` final se construye en
/// el isolate principal a partir de esta estructura.
typedef PkFlat = ({String id, int ctId, String label, double lat, double lng});

/// Versión de [PkEntity.fromGeoJson] apta para `compute()`: recibe el JSON
/// SIN decodificar (`raw`, un `String` — barato de copiar entre isolates
/// frente al árbol de objetos ya decodificado) y hace el `jsonDecode` +
/// parseo entero dentro del isolate, para que ese trabajo no corra en el
/// hilo de UI. Devuelve [PkFlat] en vez de `PkEntity` para no copiar
/// `LatLng` de vuelta.
List<PkFlat> parsePksFlat(({String raw, int ctId}) args) {
  if (args.raw.isEmpty) return const [];
  final decoded = jsonDecode(args.raw);
  final json = decoded is Map<String, dynamic>
      ? decoded
      : (decoded as Map).cast<String, dynamic>();
  final features = json['features'] as List? ?? const [];
  final result = <PkFlat>[];

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

      final properties = f['properties'] as Map<String, dynamic>? ?? const {};

      final rawLabel = properties['pk'] ??
          properties['label'] ??
          properties['name'] ??
          properties['nombre'];
      final label = rawLabel != null ? rawLabel.toString() : '';

      final rawId = properties['id'] ?? properties['pk_id'];
      final id =
          rawId != null ? rawId.toString() : '${args.ctId}_${result.length}';

      result.add((id: id, ctId: args.ctId, label: label, lat: lat, lng: lng));
    } catch (_) {
      continue;
    }
  }
  return result;
}

/// Reconstruye un [PkEntity] a partir de [PkFlat] (isolate principal, tras
/// `compute()`).
PkEntity pkFromFlat(PkFlat flat) => PkEntity(
      id: flat.id,
      ctId: flat.ctId,
      label: flat.label,
      point: LatLng(flat.lat, flat.lng),
    );
