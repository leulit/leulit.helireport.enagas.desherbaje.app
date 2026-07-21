# `gis_json` — spec de render para el frontend web

Georreferenciación de captura de la media de campo (app desherbaje). Foto → un punto con rumbo.
Vídeo → una traza de puntos con rumbo por vértice.

Autoridad del esquema: el cliente móvil. Builder en
`lib/core/gis/media_gis_geojson.dart`. Implementación de referencia del parseo en
`lib/core/gis/media_gis_map_geometry.dart` — replicarla evita repetir los errores ya resueltos ahí.

---

## 1. De dónde sale el dato

Columna `imagenes_segmento.gis_json` (`LONGTEXT NULL`, migración 011).

Llega en el array `imagenes[]` de cada segmento, en todos los endpoints que pasan por
`SegmentosService.enrich()`:

| Endpoint |
|---|
| `GET /api/enagas/v1/segmentos/contratista` |
| `GET /api/enagas/v1/segmentos/bycts/:cts` |
| `GET /api/enagas/v1/segmentos/operador/:ctscsv` |
| `GET /api/enagas/v1/segmentos/byid/:id` |
| `GET /api/enagas/v1/segmentos/byestado` |

Fila de `imagenes[]`:

```json
{
  "id": 4821,
  "segmento_id": 137,
  "tipo_foto": "antes",
  "filename": "1753086843_IMG_0042.jpg",
  "url": "/segmentos/thumbdb/4821/0/0",
  "mime_type": "image/jpeg",
  "tamanyo_bytes": 2841923,
  "capturada_at": "2026-07-21T09:14:03.000Z",
  "subida_at": "2026-07-21T09:31:12.000Z",
  "subida_por": 42,
  "upload_id": null,
  "status": null,
  "estadotransmision": "complete",
  "gis_json": "{\"type\":\"FeatureCollection\",...}"
}
```

### Tres cosas que rompen si se ignoran

1. **`gis_json` es un STRING, no un objeto.** El backend lo guarda y lo devuelve verbatim, sin
   parsear. Hay que hacer `JSON.parse()`. Ojo: el `ubicacion_gis` del segmento sí viene ya
   parseado como objeto — no son simétricos.
2. **`gis_json` puede ser `null`.** Permiso de ubicación denegado, sin fix GPS, media elegida de
   galería, o fila anterior a la migración 011. No es un error: la media es válida y se muestra,
   simplemente no se pinta nada en el mapa.
3. **Foto y vídeo comparten tabla.** `imagenes[]` trae los dos. Se distinguen así:

   ```js
   const esVideo = row.upload_id !== null || (row.mime_type || '').startsWith('video/');
   ```

   El `kind` dentro del `gis_json` (`"photo"` / `"video"`) dice lo mismo y es más directo si ya
   has parseado. Con `gis_json` null, la fila sigue siendo distinguible por `upload_id`/`mime_type`.

Para vídeo, además: `status` debe ser `"disponible"` para que la URL de reproducción sirva algo.
`iniciado` / `recibido` / `convirtiendo` → 404. `error` → la conversión falló. **El `gis_json` es
independiente de `status`**: existe desde el init, así que la traza se puede pintar aunque el vídeo
aún se esté convirtiendo.

---

## 2. Esquema

Top-level siempre `FeatureCollection` con **exactamente un** `Feature`. Orden de coordenadas
GeoJSON estándar: **`[lon, lat]`**. Leaflet usa `[lat, lng]` → hay que invertir.

### 2.1 Foto

```json
{
  "type": "FeatureCollection",
  "features": [{
    "type": "Feature",
    "geometry": { "type": "Point", "coordinates": [-3.703790, 40.416775, 667.4] },
    "properties": {
      "kind": "photo",
      "source": "camera",
      "heading": 213.7,
      "heading_accuracy": 4.5,
      "gps_heading": 210.2,
      "accuracy_m": 4.8,
      "altitude_m": 667.4,
      "speed_mps": 0.0,
      "captured_at": "2026-07-21T09:14:03.412Z",
      "user_id": 42,
      "os": "android",
      "os_version": "14",
      "device_model": "SM-A536B",
      "app_version": "1.0.4+104"
    }
  }]
}
```

`coordinates`: `[lon, lat]` o `[lon, lat, alt]`. La altitud puede faltar — no asumir longitud 3.

### 2.2 Vídeo

```json
{
  "type": "FeatureCollection",
  "features": [{
    "type": "Feature",
    "geometry": {
      "type": "LineString",
      "coordinates": [
        [-3.703790, 40.416775, 667.4, 213.7, 1784629243412],
        [-3.703812, 40.416801, 667.1, 214.9, 1784629244412],
        [-3.703836, 40.416829, 666.8, 216.2, 1784629245412]
      ]
    },
    "properties": {
      "kind": "video",
      "source": "camera",
      "coord_format": ["lon", "lat", "alt", "heading_deg", "t_epoch_ms"],
      "sample_interval_s": 1,
      "started_at": "2026-07-21T09:14:03.412Z",
      "ended_at": "2026-07-21T09:14:05.412Z",
      "user_id": 42,
      "os": "android",
      "os_version": "14",
      "device_model": "SM-A536B",
      "app_version": "1.0.4+104"
    }
  }]
}
```

**Coordenada de vídeo = 5 elementos: `[lon, lat, alt, heading_deg, t_epoch_ms]`.**

- Es una extensión propia. RFC 7946 deja los elementos más allá del tercero como "no
  especificados y ambiguos", así que **no se lo pases a `L.geoJSON()` ni a OpenLayers directamente
  esperando el rumbo**: leen `[0]` y `[1]` y descartan el resto en silencio. La línea se pintaría
  bien y el rumbo se perdería entero. Parseo manual.
- `alt` y `heading_deg` pueden ser `null` **dentro del array**. Un vértice sin rumbo es
  `[-3.70, 40.41, null, null, 1784629243412]` — sigue siendo un vértice válido con posición.
- `t_epoch_ms` es epoch ms **UTC absoluto**, no un offset relativo al inicio del vídeo. Para el
  offset dentro del vídeo: `t_epoch_ms - Date.parse(properties.started_at)`.
- Muestreo nominal 1/seg (`sample_interval_s`), pero **no garantizado uniforme**: si el GPS pierde
  fix hay huecos. Para sincronizar traza con reproducción, usar `t_epoch_ms`, nunca el índice del
  vértice.

### 2.3 Casos degradados — todos legítimos, ninguno es un fallo

| Situación | Qué llega |
|---|---|
| Vídeo con 1 sola muestra | `geometry.type === "Point"`, `coordinates` = **un array de 5**, no anidado |
| Vídeo con 0 muestras | `geometry: null` |
| Foto sin fix GPS | `geometry: null` |
| Media de galería | `geometry: null`, `properties.source === "gallery"` |
| Sin GPS en absoluto | `gis_json` = `null` (la columna) |

Con `geometry: null` el `Feature` y sus `properties` siguen ahí: `kind`, `source`, `user_id`, `os`,
`device_model`, `app_version` son explotables aunque no haya nada que pintar. RFC 7946 admite
`geometry: null` — no es JSON malformado.

`source: "gallery"` implica siempre `geometry: null` y `properties` **sin** el bloque de muestra
(sin `heading`, `accuracy_m`, `captured_at`, `started_at`…). No asumir que esas claves existen.

### 2.4 Rumbos

- `properties.heading` (foto) y `heading_deg` (vértice de vídeo): azimut de **brújula**, 0..360,
  0 = norte **magnético**, sentido horario. En la Península la declinación es ~0–2°: irrelevante
  para visualización, a tener en cuenta si algún día se cruza con datos de rumbo verdadero.
- `properties.gps_heading` (solo foto): course-over-ground del GPS. Es el rumbo de **movimiento**,
  no el de la cámara, y es basura con el operador parado. Usar solo como fallback de `heading`.
- `heading_accuracy` en grados; puede ser `null` (iOS no lo reporta de forma utilizable).

---

## 3. Parseo

```js
/** Devuelve null si no hay nada pintable. */
function parsePhotoGis(gisJsonString) {
  if (!gisJsonString) return null;
  let fc;
  try { fc = JSON.parse(gisJsonString); } catch { return null; }

  const feature = fc?.features?.[0];
  const coords = feature?.geometry?.coordinates;
  if (!Array.isArray(coords) || coords.length < 2) return null;

  const props = feature.properties ?? {};
  const h = props.heading ?? props.gps_heading;

  return {
    lat: coords[1],                                   // GeoJSON = [lon, lat]
    lon: coords[0],
    alt: typeof coords[2] === 'number' ? coords[2] : null,
    heading: typeof h === 'number' ? h : null,
    accuracyM: props.accuracy_m ?? null,
    source: props.source ?? null,
  };
}

/** Devuelve [] si no hay traza. Cubre LineString y el Point degradado. */
function parseVideoTrack(gisJsonString) {
  if (!gisJsonString) return [];
  let fc;
  try { fc = JSON.parse(gisJsonString); } catch { return []; }

  const geometry = fc?.features?.[0]?.geometry;
  const coords = geometry?.coordinates;
  if (!Array.isArray(coords) || coords.length === 0) return [];

  const vertex = c => (Array.isArray(c) && c.length >= 2)
    ? {
        lat: c[1],
        lon: c[0],
        alt: typeof c[2] === 'number' ? c[2] : null,
        heading: typeof c[3] === 'number' ? c[3] : null,
        tMs: typeof c[4] === 'number' ? c[4] : null,
      }
    : null;

  // 1 muestra → Point, coords ES el array de 5 (no una lista de arrays).
  if (geometry.type === 'Point') {
    const v = vertex(coords);
    return v ? [v] : [];
  }
  return coords.map(vertex).filter(Boolean);
}
```

Ambos parsers son **totales**: JSON inválido, `geometry: null` o coordenada corta devuelven
`null`/`[]`, nunca lanzan. La media se muestra igual; solo no se pinta.

---

## 4. Render

### 4.1 Foto — marcador + flecha de encuadre

Marcador en el punto. Si hay `heading`, flecha que arranca en el punto y apunta al rumbo: indica
hacia dónde miraba la cámara, que es lo que el revisor necesita para situar lo que ve en la foto.

Geometría de la flecha en `media_gis_map_geometry.dart:121` (`arrowGeometry`): asta de 25 m, cabeza
en V a ±150° de la punta y 35% de su longitud. Se construye con la fórmula de destino great-circle
(`destinationPoint`, R = 6371000 m), no con offsets en píxeles — así la flecha escala con el zoom
igual que el resto de la geometría.

Sin `heading`: solo el marcador. No inventar una orientación por defecto.

### 4.2 Vídeo — polilínea + banda de dirección

Polilínea sobre los vértices. Encima, una banda semitransparente al lado hacia el que miraba la
cámara: de un vistazo se ve qué franja del terreno quedó grabada.

Dos avisos con coste real, ya pagados en el móvil:

**Simplificar antes de nada.** La traza cruda a 1 Hz con el operador parado o andando despacio trae
puntos casi duplicados y microretrocesos. Ramer-Douglas-Peucker con ε = 4 m
(`simplifyTrack`) — sin esto los rumbos derivados de la tangente saltan de forma errática.

**Emitir trapecios, no un polígono único.** La primera versión (`directionBandPolygon`) construía
un solo anillo `[traza..., offset invertido]`; con GPS ruidoso se auto-intersecta y la regla
even-odd abre agujeros por toda la banda. La versión buena (`directionBandTrapezoids`) emite un
polígono independiente por segmento, compartiendo arista con el siguiente: un tramo degenerado
estropea su trapecio y solo el suyo.

Detalles de esa implementación que conviene replicar:

- Los vértices sin rumbo **heredan el más cercano**, rellenando hacia delante y luego hacia atrás.
  Sin esto la banda se corta en cada hueco de rumbo.
- El lado del desplazamiento (izquierda/derecha de la marcha) se decide **una vez para toda la
  traza**, sumando `angleDiff(tangente, rumbo)` de todos los vértices y quedándose con el signo.
  Decidirlo por vértice hace que la banda se cruce sola en cada oscilación del GPS.
- La tangente en el vértice `i` es el rumbo de la cuerda `P[i-1] → P[i+1]`, no la del segmento
  anterior.
- Si ningún vértice trae rumbo → no hay banda. Solo la polilínea.

### 4.3 Popup

`captured_at` / `started_at`+`ended_at`, `accuracy_m`, `device_model`, `app_version`. Con
`source: "gallery"` conviene decirlo explícito: esa media **no** se capturó en el sitio y no tiene
georreferencia propia.

---

## 5. Fixtures de test

Los cinco casos que hay que tener en el banco de pruebas — los cuatro últimos son los que rompen
implementaciones que solo probaron el camino feliz:

1. Foto normal: `Point` de 3 elementos + `heading`.
2. Foto sin altitud: `Point` de **2** elementos.
3. Vídeo de 1 muestra: `Point` cuyo `coordinates` es un array de **5**, sin anidar.
4. Vídeo con vértices sin rumbo intercalados: `[lon, lat, null, null, t]` en medio de la traza.
5. `geometry: null` con `properties.source === "gallery"`.

Más: `gis_json` a `null` en la fila, y `gis_json` con JSON corrupto. Ninguno de los dos debe
impedir que la media se liste y se abra.
