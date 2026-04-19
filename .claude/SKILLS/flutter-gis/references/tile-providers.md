# Tile Provider Catalog

## Provider Comparison

| Provider | Free tier | Max zoom | Attribution required | Best for |
|---|---|---|---|---|
| OpenStreetMap | Yes (with limits) | 19 | Yes — "© OpenStreetMap contributors" | Development, low traffic |
| ESRI World Imagery | Yes (non-commercial) | 23 | Yes — "ESRI, Maxar, GeoEye..." | Satellite, production |
| IGN PNOA España | Yes (public) | 20 | Yes — "© IGN España" | Spain orthophoto |
| IGN Base España | Yes (public) | 20 | Yes — "© IGN España" | Spain topographic |
| MapTiler | Freemium | 22 | Yes | Commercial, vector |
| NASA GIBS | Yes | 9 (varies) | Yes | Scientific/temporal |
| Stadia Maps | Freemium | 20 | Yes | OSM-based, reliable |

---

## URL Templates

### OpenStreetMap (development only — enforce User-Agent)
```
https://tile.openstreetmap.org/{z}/{x}/{y}.png
```
> ⚠️ OSM's public tile servers prohibit heavy usage. For production, self-host or use a paid CDN.

### ESRI World Imagery (satellite)
```
https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}
```
Note: ESRI uses `{z}/{y}/{x}` order (row/col), not `{z}/{x}/{y}`.

### ESRI World Topo Map
```
https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}
```

### IGN PNOA Máxima Actualidad (WMTS)
```
https://www.ign.es/wmts/pnoa-ma?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0
  &LAYER=OI.OrthoimageCoverage&STYLE=default
  &TILEMATRIXSET=GoogleMapsCompatible
  &TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png
```

### IGN Mapa Base Raster (WMTS)
```
https://www.ign.es/wmts/ign-base?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0
  &LAYER=IGNBaseTodo&STYLE=default
  &TILEMATRIXSET=GoogleMapsCompatible
  &TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png
```

### IGN Cartografía Catastral (WMTS)
```
https://ovc.catastro.meh.es/cartografia/INSPIRE/spadgcwmts.aspx?
  SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0
  &LAYER=Catastro&STYLE=inspire_common:DEFAULT
  &TILEMATRIXSET=GoogleMapsCompatible
  &TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png
```

### NASA GIBS (example: Blue Marble)
```
https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/BlueMarble_ShadedRelief/default/GoogleMapsCompatible/{z}/{y}/{x}.jpg
```

---

## flutter_map TileLayer Configuration

```dart
TileLayer(
  urlTemplate: '...', // URL template above
  tileProvider: CancellableNetworkTileProvider(
    // silently cancel in-flight requests when tile leaves viewport
  ),
  userAgentPackageName: 'com.yourcompany.yourapp', // required by OSM & IGN
  maxNativeZoom: 19,    // prevents upscaling beyond available tiles
  minNativeZoom: 1,
  keepBuffer: 2,        // tiles to cache around viewport
  panBuffer: 1,         // tiles to load outside viewport
  errorTileCallback: (tile, error, stackTrace) {
    // log tile errors without crashing
    debugPrint('Tile error at ${tile.coordinates}: $error');
  },
),
```

## Layering Strategy

For most Spanish projects: base ESRI + optional PNOA overlay gives best coverage.

```dart
// 1. ESRI global base (always visible)
TileLayer(urlTemplate: esriUrl, tileProvider: CancellableNetworkTileProvider()),
// 2. PNOA overlay toggle (Spain high-res, toggled by user)
if (showPnoa)
  TileLayer(urlTemplate: pnoaUrl, tileProvider: CancellableNetworkTileProvider()),
// 3. Catastro overlay (semi-transparent when needed)
if (showCatastro)
  TileLayer(urlTemplate: catastroUrl, opacity: 0.6, tileProvider: CancellableNetworkTileProvider()),
```

## Attribution Requirements

Always include attribution — both legally required and good practice:

```dart
RichAttributionWidget(
  attributions: [
    TextSourceAttribution(
      'OpenStreetMap contributors',
      onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright')),
    ),
    TextSourceAttribution('IGN España'),
    LogoSourceAttribution(Image.asset('assets/esri_logo.png')),
  ],
),
```
