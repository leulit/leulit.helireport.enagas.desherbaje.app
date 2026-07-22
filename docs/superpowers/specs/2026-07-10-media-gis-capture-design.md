# GIS en captura de foto/vídeo — Diseño

**Fecha:** 2026-07-10
**Estado:** propuesto (pendiente sign-off del responsable)
**Módulo:** Desherbaje — captura de media georreferenciada

---

## 1. Objetivo

Al capturar una **foto** o grabar un **vídeo** desde la cámara propia de la app,
registrar automáticamente (sin aprobación del usuario) la posición y la
dirección a la que apunta el dispositivo, y persistirlo en un campo `gis_json`
(GeoJSON) por media para enviarlo al backend.

- **Foto:** un único punto (lat, lon, alt) + rumbo en el instante del disparo.
- **Vídeo:** el track completo (1 muestra/seg) durante toda la grabación, para
  reconstruir por dónde y hacia dónde se grabó.

La captura del track de vídeo es **independiente** del `GpsBackgroundService`
(work-track de jornada) y debe poder funcionar **simultáneamente** con él.

Si falta permiso de ubicación o no hay fix GPS, la captura **no se bloquea**:
la media se guarda igual con `gis_json = null`.

---

## 2. Decisiones cerradas

| # | Decisión | Valor |
|---|---|---|
| D1 | Fuente de rumbo | `flutter_rotation_sensor` (azimuth), funciona parado. Sustituye a `flutter_compass` (roto en AGP 8, sin `namespace`). |
| D2 | Metadatos de dispositivo | `device_info_plus` (`os`, `os_version`, `device_model`) + `package_info_plus` (`app_version`). |
| D3 | Almacén | **Solo** columna nueva `gis_json TEXT`. |
| D4 | Columnas eliminadas | `latitud`, `longitud`, `fixed_latitud`, `fixed_longitud` en **ambas** tablas (`imagenes_segmento` y `videos_segmento`). Ninguna se poblaba. |
| D5 | Top-level GeoJSON | `FeatureCollection` (unifica foto/vídeo). |
| D6 | Geometría foto | `Point` estándar `[lon, lat, alt]`; rumbo y extras en `properties`. |
| D7 | Geometría vídeo | `LineString` con **coordenada custom** `[lon, lat, alt, heading_deg, t_epoch_ms]` por vértice. Evita arrays paralelos gigantes en vídeos largos. |
| D8 | Muestreo vídeo | Por tiempo, **1 muestra/seg** (`distanceFilter 0`). |
| D9 | `t` de la coordenada | epoch **milisegundos UTC** (absoluto). Property `coord_format` autodescriptiva. |
| D10 | Degradación vídeo | 0 muestras → `gis_json` null; 1 muestra → feature `Point`; ≥2 → `LineString`. |
| D11 | Ejecución del muestreo | `MediaGisRecorder` foreground, vivo mientras la cámara está abierta. Streams propios (posición + rotación), independientes del `GpsBackgroundService`. |
| D12 | Media de galería | Sin GIS (`gis_json` null). Solo la cámara propia georreferencia. |

> ⚠️ GeoJSON usa orden **`[lon, lat]`**, no `[lat, lon]`.

---

## 3. Esquema `gis_json`

### 3.1 Foto (Point)

```json
{
  "type": "FeatureCollection",
  "features": [{
    "type": "Feature",
    "geometry": { "type": "Point", "coordinates": [-3.7038, 40.4168, 650.0] },
    "properties": {
      "kind": "photo",
      "heading": 123.4,
      "heading_accuracy": 5.0,
      "gps_heading": 0.0,
      "accuracy_m": 4.2,
      "altitude_m": 650.0,
      "speed_mps": 0.0,
      "captured_at": "2026-07-10T09:12:33.000Z",
      "user_id": 42,
      "os": "android",
      "os_version": "14",
      "device_model": "Pixel 7",
      "app_version": "1.0.4+104"
    }
  }]
}
```

### 3.2 Vídeo (LineString, coordenada custom)

```json
{
  "type": "FeatureCollection",
  "features": [{
    "type": "Feature",
    "geometry": {
      "type": "LineString",
      "coordinates": [
        [-3.7038, 40.4168, 650.0, 120.0, 1752138753000],
        [-3.7039, 40.4169, 650.5, 121.5, 1752138754000]
      ]
    },
    "properties": {
      "kind": "video",
      "coord_format": ["lon", "lat", "alt", "heading_deg", "t_epoch_ms"],
      "sample_interval_s": 1,
      "started_at": "2026-07-10T09:12:33.000Z",
      "ended_at": "2026-07-10T09:15:33.000Z",
      "user_id": 42,
      "os": "android",
      "os_version": "14",
      "device_model": "Pixel 7",
      "app_version": "1.0.4+104"
    }
  }]
}
```

Con 1 muestra → `geometry` degrada a `Point` `[lon,lat,alt,heading,t]` (property
`kind` sigue `"video"`). Con 0 muestras → `gis_json = null`.

---

## 4. Arquitectura

### 4.1 Componentes nuevos (`lib/core/gis/`)

- **`capture_meta.dart`** — helper cacheado (una lectura): `os`, `os_version`,
  `device_model` (`device_info_plus`) + `app_version` (`package_info_plus`).
  Expone `Future<CaptureMeta> captureMeta()` memoizado.
- **`media_gis_recorder.dart`** — `MediaGisRecorder` (Dart plano, no GetxService;
  su ciclo de vida es el de la página de cámara):
  - `start()` — pide permiso `whileInUse`; abre `Geolocator.getPositionStream`
    (1 s) + `RotationSensor.orientationStream`; guarda `_lastPosition`,
    `_lastHeading`. Si el permiso se deniega, queda en modo "sin GIS".
  - `snapshotPhoto()` → `MediaGisSample?` (últimos valores en el instante del
    disparo).
  - `startTrack()` / `stopTrack()` → arranca/para un `Timer.periodic(1s)` que
    empuja `MediaGisSample` a una lista; `stopTrack` devuelve `List<MediaGisSample>`.
  - `dispose()` — cancela suscripciones y timer.
  - **Independiente** del `GpsBackgroundService`: no comparte streams ni estado.
    Riesgo a verificar en dispositivo real: dos suscripciones `geolocator`
    concurrentes (foto/vídeo + work-track). geolocator lo soporta; confirmar en
    Android físico.
- **`media_gis_geojson.dart`** — funciones **puras** y testeables:
  - `String? buildPhotoGeoJson(MediaGisSample?, {required int? userId, required CaptureMeta meta})`
  - `String? buildVideoGeoJson(List<MediaGisSample>, {required int? userId, required CaptureMeta meta})`
  - Devuelven `null` cuando no hay muestra útil.

`MediaGisSample`: `{ double lat, lon; double? alt, headingDeg, accuracyM, gpsHeading, speedMps; DateTime tsUtc; }`.

### 4.2 Cambios en `CameraCapturePage`

- Instancia y `start()` del `MediaGisRecorder` en `_initCamera` (tras permiso).
- `_takePhoto`: `gis = _recorder.snapshotPhoto()`.
- `_startVideo`: `_recorder.startTrack()`; `_stopVideo`: `track = _recorder.stopTrack()`.
- `dispose`: `_recorder.dispose()`.
- Retorno ampliado: `({String path, bool isVideo})` →
  `({String path, bool isVideo, Object? gis})` donde `gis` es
  `MediaGisSample?` (foto) o `List<MediaGisSample>` (vídeo).

### 4.3 Cambios en `SegmentoDetalleController`

- `_addImagen` y `_saveVideoFromPath` reciben el payload GIS.
- Construyen `gis_json` vía el builder con `user.value?.id` + `captureMeta()`.
- Setean `entity.gisJson` antes de `saveLocal`.
- Rama galería: `gis_json = null` (sin cambios de captura).

### 4.4 Entidades

`ImagenSegmentoEntity` y `VideoSegmentoEntity`:
- **Eliminar** campos `latitud`, `longitud`, `fixedLatitud`, `fixedLongitud`
  (y sus entradas de enum, `toMap`, `fromMap`, `toJson`, `fromJson`, `copyWith`).
- **Añadir** `String? gisJson` + enum `gisJson('gis_json')` + en
  `toMap`/`fromMap`/`toJson`/`fromJson`/`copyWith`.
- `toJson` envía `gis_json` al backend.

### 4.5 Migración de esquema (ambos stores)

`ImagenLocalStore` / `VideoLocalStore`: `schemaVersion 2 → 3`. Se **añade**
bloque `from < 3 && to >= 3` (no se reescriben v1/v2). Como SQLite antiguo de
Android no garantiza `DROP COLUMN`, se hace **table-rebuild**:

```sql
CREATE TABLE <tabla>_new ( ... columnas finales sin lat/lon, con gis_json TEXT ... );
INSERT INTO <tabla>_new (<cols comunes>) SELECT <cols comunes> FROM <tabla>;
DROP TABLE <tabla>;
ALTER TABLE <tabla>_new RENAME TO <tabla>;
-- recrear índices: idx_<tabla>_seg, idx_<tabla>_remote, idx_<tabla>_segclient
```

App no está en producción → sin backfill; DBs de dev se migran limpio.

---

## 5. Permisos / plataforma

- Ubicación `whileInUse` basta (captura es foreground). Android ya declara
  `ACCESS_FINE_LOCATION`; iOS ya tiene las `NSLocation…UsageDescription`.
- Magnetómetro (`flutter_rotation_sensor`) y `device_info_plus` /
  `package_info_plus`: sin permisos.
- Sin cambios de manifest/Info.plist.

---

## 6. Testing

- **Nuevo** `test/core/gis/media_gis_geojson_test.dart` (obligatorio): Point,
  LineString multi-punto, degradación 0/1 muestra, orden `[lon,lat]`, presencia
  de `user_id`/`os`/`os_version`/`device_model`/`app_version`, formato de
  coordenada de vídeo.
- **Actualizar** tests de store/entidad de imagen y vídeo por columnas
  eliminadas + `gis_json` (round-trip `toMap`/`fromMap`, migración v2→v3).

---

## 7. Cierre / documentación

- Contrato backend pendiente: añadir `gis_json` (GeoJSON) a foto y vídeo; anotar
  que `latitud/longitud/fixed_*` se eliminan del payload de ambas.
- `docs/ARCHITECTURE_REFERENCE.md`: entidades (campos), nuevos ficheros
  `lib/core/gis/*`, deps nuevas en `pubspec.yaml`.

---

## 8. Ficheros afectados

**Nuevos**
- `lib/core/gis/capture_meta.dart`
- `lib/core/gis/media_gis_recorder.dart`
- `lib/core/gis/media_gis_geojson.dart`
- `test/core/gis/media_gis_geojson_test.dart`

**Modificados**
- `pubspec.yaml` (+ `flutter_rotation_sensor`, `device_info_plus`, `package_info_plus`)
- `lib/presentation/camera/camera_capture_page.dart`
- `lib/presentation/detalle/segmento_detalle_controller.dart`
- `lib/domain/entities/imagen_segmento_entity.dart`
- `lib/domain/entities/video_segmento_entity.dart`
- `lib/data/sync/imagen_local_store.dart`
- `lib/data/sync/video_local_store.dart`
- tests de store/entidad existentes
- `docs/ARCHITECTURE_REFERENCE.md`, contrato backend

---

## 9. Riesgos

1. Dos streams `geolocator` concurrentes (media-GIS + work-track). Verificar en
   Android físico que ambos entregan sin conflicto.
2. `flutter_rotation_sensor` — confirmar build en iOS + Android del proyecto.
3. Precisión de rumbo del magnetómetro sin calibrar (interferencia metálica en
   campo). Se guarda `heading_accuracy` para poder filtrar aguas abajo.
