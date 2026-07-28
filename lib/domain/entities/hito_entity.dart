import 'dart:convert';

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

/// Estructura plana (solo primitivas) que traslada el resultado del parseo
/// GeoJSON entre isolates con el menor coste de copia posible: `lat`/`lng`
/// sueltos en vez de `LatLng`. El `LatLng`/`HitoEntity` final se construye
/// en el isolate principal a partir de esta estructura.
typedef HitoFlat = ({String id, int ctId, String label, double lat, double lng});

/// Versión de [HitoEntity.fromGeoJson] apta para `compute()`: recibe el
/// JSON SIN decodificar (`raw`, un `String` — barato de copiar entre
/// isolates frente al árbol de objetos ya decodificado) y hace el
/// `jsonDecode` + parseo entero dentro del isolate, para que ese trabajo no
/// corra en el hilo de UI. Devuelve [HitoFlat] en vez de `HitoEntity` para
/// no copiar `LatLng` de vuelta.
List<HitoFlat> parseHitosFlat(({String raw, int ctId}) args) {
  if (args.raw.isEmpty) return const [];
  final decoded = jsonDecode(args.raw);
  final json = decoded is Map<String, dynamic>
      ? decoded
      : (decoded as Map).cast<String, dynamic>();
  final features = json['features'] as List? ?? const [];
  final result = <HitoFlat>[];

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

      final rawLabel = properties['hito'] ??
          properties['label'] ??
          properties['name'] ??
          properties['nombre'] ??
          properties['pk'];
      final label = rawLabel != null ? rawLabel.toString() : '';

      final rawId =
          properties['id'] ?? properties['hito_id'] ?? properties['pk_id'];
      final id =
          rawId != null ? rawId.toString() : '${args.ctId}_${result.length}';

      result.add((id: id, ctId: args.ctId, label: label, lat: lat, lng: lng));
    } catch (_) {
      continue;
    }
  }
  return result;
}

/// Reconstruye un [HitoEntity] a partir de [HitoFlat] (isolate principal,
/// tras `compute()`).
HitoEntity hitoFromFlat(HitoFlat flat) => HitoEntity(
      id: flat.id,
      ctId: flat.ctId,
      label: flat.label,
      point: LatLng(flat.lat, flat.lng),
    );
