---
name: flutter-gis
description: >
  Flutter GIS and cartography skill — use this whenever the project involves
  maps, geographic information, spatial data, coordinates, tile providers,
  WMS/WMTS services, GeoJSON, shapefiles, GPS, geofencing, route calculation,
  or any location-aware feature. Triggers on mentions of flutter_map, latlong2,
  proj4dart, EPSG, GIS, WMTS, WMS, PNOA, IGN, OpenStreetMap, Mapbox, ESRI,
  coordinates, polygons on maps, pipelines on maps, or geographic data processing.
  Always apply alongside flutter-core. Requires advanced mathematics: coordinate
  projections, linear algebra, trigonometry, spatial indexing algorithms.
---

# Flutter GIS Skill

> Always apply **flutter-core** in parallel. This skill extends it for GIS.

## Core Stack

| Package | Version | Purpose |
|---|---|---|
| `flutter_map` | `^8.2.2` | Primary map widget (Leaflet-based, vendor-free) |
| `latlong2` | `^0.9.1` | Coordinate types `LatLng`, distance calculations |
| `proj4dart` | `^2.1.0` | Coordinate Reference System transformations |
| `flutter_map_cancellable_tile_provider` | latest | Cancellable tile loading (critical for web perf) |
| `cached_network_image` | `^3.4.1` | Tile caching (supplement to tile providers) |
| `geolocator` | `^13.0.0` | GPS position, permission handling |
| `flutter_map_location_marker` | latest | User location layer |

---

## Mathematics Requirements

GIS work requires solid command of the following. Never approximate or skip:

### Coordinate Systems & Projections
- **EPSG:4326** (WGS84): geographic lat/lng in degrees — the universal GPS standard
- **EPSG:3857** (Web Mercator): projected x/y in metres — used by OSM, Google, ESRI tile services
- **EPSG:25830** (UTM zone 30N): used by Spanish IGN/PNOA services

```dart
import 'package:proj4dart/proj4dart.dart';

// Define a custom CRS (e.g. Spanish UTM zone 30N)
final utm30n = Projection.add('EPSG:25830',
  '+proj=utm +zone=30 +ellps=GRS80 +units=m +no_defs');

// Transform: WGS84 → UTM30N
final wgs84 = Projection.get('EPSG:4326')!;
final pointWgs84 = Point(x: -3.7038, y: 40.4168); // Madrid
final pointUtm = wgs84.transform(utm30n, pointWgs84);
// → Point(x: 440162.0, y: 4474338.0)

// Inverse transform: UTM30N → WGS84
final pointBack = utm30n.transform(wgs84, pointUtm);
```

### Haversine Formula — Great-Circle Distance
```dart
import 'dart:math';

/// Returns distance in metres between two WGS84 coordinates.
double haversineDistance(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0; // Earth radius in metres
  final phi1 = lat1 * pi / 180;
  final phi2 = lat2 * pi / 180;
  final dPhi = (lat2 - lat1) * pi / 180;
  final dLambda = (lon2 - lon1) * pi / 180;

  final a = sin(dPhi / 2) * sin(dPhi / 2) +
      cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}
```

### Bounding Box Calculations
```dart
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

/// Compute bounding box for a list of coordinates with optional padding.
LatLngBounds boundsFromPoints(List<LatLng> points, {double paddingDeg = 0.01}) {
  final lats = points.map((p) => p.latitude);
  final lngs = points.map((p) => p.longitude);
  return LatLngBounds(
    LatLng(lats.reduce(min) - paddingDeg, lngs.reduce(min) - paddingDeg),
    LatLng(lats.reduce(max) + paddingDeg, lngs.reduce(max) + paddingDeg),
  );
}
```

### Tile Coordinate Mathematics (Slippy Map)
```dart
/// Convert WGS84 to tile X/Y at a given zoom level (OSM/WMTS standard).
({int x, int y}) latLngToTile(double lat, double lng, int zoom) {
  final n = pow(2, zoom);
  final x = ((lng + 180) / 360 * n).floor();
  final latRad = lat * pi / 180;
  final y = ((1 - log(tan(latRad) + 1 / cos(latRad)) / pi) / 2 * n).floor();
  return (x: x, y: y);
}
```

---

## Map Setup

### Basic FlutterMap with Layered Tile Providers

```dart
class MapView extends GetView<MapController> {
  const MapView({super.key});

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller.mapController,
      options: MapOptions(
        initialCenter: const LatLng(40.4168, -3.7038),
        initialZoom: 10,
        minZoom: 5,
        maxZoom: 20,
        onMapEvent: controller.onMapEvent,
      ),
      children: [
        // Base layer: ESRI World Imagery (global fallback)
        TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/'
              'World_Imagery/MapServer/tile/{z}/{y}/{x}',
          tileProvider: CancellableNetworkTileProvider(), // critical for web
          userAgentPackageName: 'com.yourcompany.yourapp',
          maxNativeZoom: 19,
        ),
        // Optional overlay: Spanish PNOA (high-res orthophoto)
        Obx(() => controller.showPnoa.value
          ? TileLayer(
              urlTemplate: 'https://www.ign.es/wmts/pnoa-ma?'
                  'SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
                  '&LAYER=OI.OrthoimageCoverage&STYLE=default'
                  '&TILEMATRIXSET=GoogleMapsCompatible'
                  '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png',
              tileProvider: CancellableNetworkTileProvider(),
              maxNativeZoom: 20,
            )
          : const SizedBox.shrink()),
        // Data layers
        Obx(() => PolylineLayer(polylines: controller.polylines)),
        Obx(() => MarkerLayer(markers: controller.markers)),
        // Attribution (legally required for OSM/ESRI)
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('ESRI World Imagery'),
            TextSourceAttribution('IGN España - PNOA'),
          ],
        ),
      ],
    );
  }
}
```

### GIS Controller Pattern

```dart
class MapController extends GetxController {
  final mc = flutter_map.MapController();
  flutter_map.MapController get mapController => mc;

  final showPnoa = false.obs;
  final markers = <Marker>[].obs;
  final polylines = <Polyline>[].obs;
  final currentBounds = Rxn<LatLngBounds>();

  void onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd) {
      currentBounds.value = mc.camera.visibleBounds;
      _loadFeaturesInView();
    }
  }

  /// Load only features within the current viewport — critical for performance.
  Future<void> _loadFeaturesInView() async {
    final bounds = currentBounds.value;
    if (bounds == null) return;
    // Pass bounds to repository — never load all features globally
    final features = await _repository.getFeaturesInBounds(bounds);
    features.fold(
      (failure) => Get.snackbar('Error', failure.message),
      (data) => _updateLayers(data),
    );
  }

  void fitBounds(List<LatLng> points) {
    final bounds = boundsFromPoints(points);
    mc.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32)));
  }

  void animateTo(LatLng target, {double zoom = 15}) {
    mc.move(target, zoom);
  }
}
```

---

## WMTS / WMS Integration

### Tile Matrix Sets
Different services use different TileMatrixSets. Always verify:

| Service | TileMatrixSet | EPSG |
|---|---|---|
| IGN PNOA | `GoogleMapsCompatible` | 3857 |
| IGN Base | `GoogleMapsCompatible` | 3857 |
| IDEE Spain | `EPSG:25830` | 25830 |
| OpenStreetMap | Standard slippy | 3857 |
| ESRI | Standard slippy | 3857 |

```dart
// WMTS URL template helper — builds correct GetTile URL
String buildWmtsUrl({
  required String baseUrl,
  required String layer,
  required String tileMatrixSet,
  String format = 'image/png',
}) {
  return '$baseUrl?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
      '&LAYER=$layer&STYLE=default'
      '&TILEMATRIXSET=$tileMatrixSet'
      '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}'
      '&FORMAT=$format';
}
```

---

## GeoJSON Processing

```dart
import 'dart:convert';

// Parse GeoJSON FeatureCollection into flutter_map Polylines
List<Polyline> geoJsonToPolylines(String rawJson, {Color color = Colors.blue}) {
  final json = jsonDecode(rawJson) as Map<String, dynamic>;
  final features = (json['features'] as List).cast<Map<String, dynamic>>();

  return features
      .where((f) => f['geometry']['type'] == 'LineString')
      .map((f) {
        final coords = (f['geometry']['coordinates'] as List)
            .cast<List>()
            .map((c) => LatLng(c[1] as double, c[0] as double)) // GeoJSON: [lng, lat]
            .toList();
        return Polyline(points: coords, color: color, strokeWidth: 3);
      })
      .toList();
}
```

> ⚠️ GeoJSON coordinate order is **[longitude, latitude]** — opposite to `LatLng(lat, lng)`. Always swap.

---

## Performance Rules for GIS

1. **Viewport culling**: never load all features — query only what's in `camera.visibleBounds`.
2. **`CancellableNetworkTileProvider`**: mandatory on web to cancel in-flight tile requests on pan/zoom.
3. **`maxNativeZoom`**: always set to avoid upscaling tiles (blurry map).
4. **Cluster markers**: for >100 markers use `flutter_map_marker_cluster` — never render raw MarkerLayer with thousands of markers.
5. **Simplify polylines**: use the Ramer-Douglas-Peucker algorithm at low zoom levels to reduce point count.
6. **Isolates for heavy parsing**: GeoJSON/shapefile parsing must happen in a `compute()` call, never on the UI thread.

```dart
// Heavy GeoJSON parsing → isolate
Future<List<Polyline>> parseGeoJsonAsync(String rawJson) {
  return compute(geoJsonToPolylines, rawJson);
}
```

---

## Spatial Queries

### Point-in-Polygon (Ray Casting)
```dart
/// Returns true if [point] is inside [polygon].
bool pointInPolygon(LatLng point, List<LatLng> polygon) {
  bool inside = false;
  int j = polygon.length - 1;
  for (int i = 0; i < polygon.length; i++) {
    if ((polygon[i].latitude > point.latitude) !=
            (polygon[j].latitude > point.latitude) &&
        point.longitude <
            (polygon[j].longitude - polygon[i].longitude) *
                    (point.latitude - polygon[i].latitude) /
                    (polygon[j].latitude - polygon[i].latitude) +
                polygon[i].longitude) {
      inside = !inside;
    }
    j = i;
  }
  return inside;
}
```

---

## Reference Files

- `references/tile-providers.md` — Tile provider catalog: OSM, ESRI, IGN PNOA, MapTiler, NASA GIBS; legal/attribution requirements
- `references/coordinate-systems.md` — EPSG codes used in Spain, proj4dart CRS definitions, UTM zones
- `references/geofencing.md` — Geofence implementation: circle/polygon detection, background location, battery optimisation
