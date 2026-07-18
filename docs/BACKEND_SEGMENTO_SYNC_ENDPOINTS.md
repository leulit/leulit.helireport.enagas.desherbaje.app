# Sincronización offline de segmentos — API para el cliente

Apps: **desherbaje** (móvil) y **webapp** (Flutter web).

Base URL: `https://<host>/api/enagas/v1`

Todos los endpoints de este documento exigen HMAC (§1). Todos los paths que aparecen abajo
son **relativos a la base URL**.

Forma de error: `{ "error": "texto" }`, salvo los `409` de vídeo (§6), que no la usan.

---

## 1. HMAC

```
X-HMAC-Signature: HMAC-SHA256(secret, `${ts}:${METHOD}:${url}`)   en hex
X-Timestamp:      epoch en ms
```

- `url` = ruta completa **incluido `/api/enagas/v1` y el querystring**.
- Ventana: **±5 min**.
- `401` es **siempre** de firma, nunca de sesión.

Excepción: el endpoint de media (§8) admite además firma en la query.

**Errores**: `401` con `Faltan headers HMAC` | `Timestamp HMAC expirado` | `Firma HMAC inválida`.

---

## 2. Orden de las llamadas

```
1. POST /segmentos/upsert                 → { id, ... }   ← id definitivo
2. POST /segmentos/{id}/imagenes               (0..n)
   POST /videos/upload (+ chunks + complete)   (0..n)
   POST /segmentos/mensajes/{id}               (0..n)
3. POST /segmentos/{id}/sync-complete
```

Tres reglas que condicionan cómo se invoca:

1. **El segmento va primero.** Su `id` de respuesta es el que se usa para colgar fotos,
   vídeos y mensajes. La identidad es siempre `id` entero; no existe `client_id`.
2. **`upsert` borra todo lo `pending` de ese segmento** (filas y ficheros). Es un reenvío
   entero del workflow, no un parche: no mandes `upsert` si solo quieres añadir una foto.
3. **No purgues los datos locales hasta el `200` de `sync-complete`.** Es la única señal de
   que el envío está completo; purgar antes pierde fotos y vídeos de campo sin aviso.

---

## 3. `POST /segmentos/upsert`

`application/json`. El `id` viaja en el **body**, no en el path.

| `id` | Efecto |
|---|---|
| `> 0` | Update parcial |
| `0`, negativo, `null` o ausente | Insert |

**Body** (ningún campo es obligatorio):

```json
{
  "id": 0,
  "tipo_actividad": "...",
  "estado": "propuesta",
  "ctname": "...",
  "nombre": "...",
  "traza": "...",
  "tipo_instalacion": "...",
  "pk_inicio": "...",
  "pk_fin": "...",
  "lat_inicio": 0.0,
  "lng_inicio": 0.0,
  "lat_fin": 0.0,
  "lng_fin": 0.0,
  "descripcion": "...",
  "fecha_inico": "...",
  "fecha_fin": "...",
  "ubicacion_gis": "…GeoJSON…",
  "longitud": 0.0
}
```

- `fecha_inico` no es una errata de este documento: es el nombre real de la columna.
- **Cualquier campo no listado se descarta en silencio**, sin error. Un campo nuevo hay que
  declararlo antes en el backend.
- `estado` no se valida: se guarda el valor que llegue.

**`200`** — entidad completa:

```json
{
  "id": 42, "ctname": "…", "nombre": "…", "traza": "…", "tipo_instalacion": "…",
  "tipo_actividad": "…", "estado": "propuesta", "pk_inicio": "…", "pk_fin": "…",
  "lat_inicio": 0.0, "lng_inicio": 0.0, "lat_fin": 0.0, "lng_fin": 0.0,
  "descripcion": "…", "fecha_inico": "…", "fecha_fin": "…", "longitud": 0.0,
  "created_at": "…", "updated_at": "…", "ubicacion_gis": { }
}
```

`ubicacion_gis` sale como **objeto GeoJSON** (o `null`), no como string.

**Errores**: `404` `Segmento no encontrado` (solo en update, si el `id` no existe).

---

## 4. `POST /segmentos/{id}/imagenes`

`multipart/form-data`.

| Campo | Oblig. | Valor |
|---|---|---|
| *(el fichero)* | sí | binario — el nombre del campo da igual |
| `tipoFoto` | sí | `antes` \| `despues` |
| `capturada_at` | no | ISO8601 (por defecto, ahora) |
| `subida_por` | no | id de usuario |

**`200`**

```json
{ "id": 123, "url": "/segmentos/thumbdb/123/0/0" }
```

`url` viene **sin el prefijo `/api/enagas/v1`**: hay que anteponerlo para usarla.

**Errores**: `400` `file es obligatorio` | `tipoFoto debe ser 'antes' o 'despues'`;
`404` `Segmento no encontrado`.

> `/operador/additem` no sirve para fotos de segmento: ignora `segmentoId` y `tipoFoto`.
> Sigue vigente para incidencias de operador.

---

## 5. `POST /segmentos/mensajes/{idSegmento}`

`application/json`.

```json
{ "mensaje": "texto", "enviado_por": 7 }
```

`mensaje` es obligatorio (no vacío). `segmento_id` en el body se ignora: manda el del path.

**`200`**

```json
{ "id": 55, "segmento_id": 42, "mensaje": "texto", "enviado_por": 7,
  "created_at": "…", "updated_at": "…", "sender_user_name": "…" }
```

**Errores**: `400` `mensaje es obligatorio`.

---

## 6. Vídeos — subida resumable

```
POST /videos/upload                      → init
POST /videos/upload/{uploadId}           → chunk
GET  /videos/upload/{uploadId}           → estado
POST /videos/upload/{uploadId}/complete  → cierre
```

Límites: fichero **2 GB**, chunk **10 MB**.

### 6.1 Init — `POST /videos/upload`

`application/json`. Nombres exactos, **camelCase**:

```json
{
  "originalFilename": "IMG_0042.MOV",
  "totalBytes": 18432000,
  "mimeType": "video/quicktime",
  "segmentoId": 42,
  "tipoFoto": "despues",
  "usuariologged": "...",
  "idusuariologged": 7
}
```

- Obligatorios: `originalFilename`, `totalBytes` (≥1), `mimeType`, `segmentoId`.
- `tipoFoto` opcional, `antes` | `despues`, por defecto `despues`.
- `segmento_id` en snake_case **no se lee**; cualquier campo no listado se descarta.

**`201`**

```json
{ "uploadId": "a1b2…", "offset": 0, "segmentoId": 42 }
```

**Errores**: `400` `segmentoId es obligatorio` | `tipoFoto debe ser 'antes' o 'despues'`.

### 6.2 Chunk — `POST /videos/upload/{uploadId}`

`application/octet-stream`, body = bytes crudos. **`PATCH` no existe: devuelve `404`.**

Cabecera obligatoria: `Upload-Offset: <byte de inicio de este chunk>`.

**`200`** → `{ "offset": 4194304 }` — el nuevo offset. Es el que se usa para el siguiente chunk.

**Errores**:

| Código | Cuerpo | Cuándo |
|---|---|---|
| `400` | `{ "error": "Header Upload-Offset requerido" }` | falta la cabecera |
| `400` | `{ "error": "Upload-Offset debe ser un entero no negativo" }` | valor inválido |
| `404` | `{ "error": "Sesión no encontrada: …" }` | `uploadId` desconocido |
| `409` | **`{ "offset": 4194304 }`** | `Upload-Offset` adelantado al servidor. Reenvía desde ese `offset`. |
| `413` | `{ "error": "Chunk supera el límite…" }` | chunk >10 MB o fichero >2 GB |

El `409` **no trae clave `error`**, solo `offset`. Reenviar un offset **anterior** no es error:
el servidor trunca y reescribe.

### 6.3 Estado — `GET /videos/upload/{uploadId}`

Para reanudar tras un corte. **`200`**

```json
{ "uploadId": "a1b2…", "offset": 4194304, "totalBytes": 18432000,
  "mimeType": "video/quicktime", "originalFilename": "IMG_0042.MOV", "complete": false }
```

`offset` = por qué byte seguir. **Errores**: `404` `Sesión no encontrada: …`.

### 6.4 Cierre — `POST /videos/upload/{uploadId}/complete`

Sin body. **`200`**

```json
{ "uploadId": "a1b2…", "id": 987, "status": "recibido" }
```

`id` = fila en `imagenes_segmento`; es el mismo `id` que aparece luego en `imagenes[]` (§7).
El vídeo aún se está convirtiendo: no es reproducible hasta `status: "disponible"` (§7).

**Errores**: `404` `Sesión no encontrada: …`;
`409` **`{ "offset": 123, "totalBytes": 18432000 }`** (faltan bytes; sin clave `error`).

> La app guarda el `uploadId` para reanudar. Si se pierde la respuesta del init, el vídeo se
> sube de cero.

---

## 7. `POST /segmentos/{id}/sync-complete`

Sin body. Se llama **después** de enviar todas las fotos, vídeos y mensajes del segmento.
Idempotente y no destructivo.

**`200`** → `{ "success": true, "id": 42 }`

**Errores**: `404` `Segmento no encontrado`.

---

## 8. `GET /segmentos/contratista`

```http
GET /segmentos/contratista?cts=CT1,CT2
```

`cts` = CSV de nombres de CT, **opcional** (1–2000 chars). Sin él devuelve todos: el backend
no conoce usuarios (el HMAC es a nivel de app), así que el filtrado por usuario lo hace la app.

**`200`** — array de segmentos en estado **`propuesta`** o **`validada`**, ordenado por `id`
descendente. Cada uno trae los campos de §3 más `imagenes[]` y `mensajes[]` (`[]` si no hay).

**Los vídeos van dentro de `imagenes[]`** — no hay array `videos[]`. Fotos y vídeos comparten
tabla y autoincrement, así que sus `id` nunca colisionan. Se distinguen por `mime_type`.

```jsonc
[
  {
    "id": 42, "estado": "propuesta", "nombre": "…", "ctname": "…",
    // …resto de campos del segmento (§3)…
    "imagenes": [
      { "id": 123, "segmento_id": 42, "tipo_foto": "antes", "filename": "…",
        "url": "/segmentos/thumbdb/123/0/0", "mime_type": "image/jpeg",
        "tamanyo_bytes": 0, "latitud": null, "longitud": null,
        "capturada_at": "…", "subida_at": "…", "subida_por": 7,
        "upload_id": null, "status": null, "estadotransmision": "complete" },
      { "id": 987, "segmento_id": 42, "tipo_foto": "despues", "filename": "…",
        "url": "/segmentos/thumbdb/987/0/0", "mime_type": "video/mp4",
        "upload_id": "a1b2…", "status": "disponible", "estadotransmision": "complete" }
    ],
    "mensajes": [
      { "id": 55, "segmento_id": 42, "mensaje": "texto", "enviado_por": 7,
        "created_at": "…", "updated_at": "…", "sender_user_name": "…" }
    ]
  }
]
```

**`status` solo aplica a vídeos** (`null` en fotos). Hay que mirarlo antes de reproducir:

| `status` | Qué hacer |
|---|---|
| `iniciado`, `recibido`, `convirtiendo` | Pintar "procesando". La URL devuelve **404**. |
| `disponible` | Reproducible. |
| `error` | La conversión falló. El motivo solo está en el log del servidor. |

---

## 9. Media — `GET /segmentos/thumbdb/{id}/{width}/{height}`

Un solo endpoint sirve fotos y vídeos. Sustituye a `/segmentos/imagen/{id}` y a
`/videos/download/{uploadId}.mp4`, **ambos retirados**.

- `width=0&height=0` → original sin procesar. Otros valores → thumbnail JPEG (solo fotos).
- El cliente distingue foto de vídeo por el `Content-Type` de la respuesta.
- Vídeos: se sirven con **`Range`** (`200` sin cabecera, `206` con ella, `416` fuera de rango),
  así el reproductor hace seek sin bajar el fichero entero.

**Errores**: `404` `Imagen no encontrada` | `Vídeo no disponible` (`status != 'disponible'`).

### Firma en la query

El navegador no puede mandar cabeceras en un `<video src="...">`. Por eso **este endpoint**
(y solo este) acepta la firma en la query:

```
sig = HMAC-SHA256(secret, `${ts}:GET:/api/enagas/v1/segmentos/thumbdb/987/0/0`)

GET /api/enagas/v1/segmentos/thumbdb/987/0/0?ts=1752691200000&sig=<hex>
```

- Mismo secreto que el HMAC de cabeceras. **La firma cubre solo el pathname**, sin querystring
  (la propia `sig` viaja ahí). `width`/`height` van en el path, así que queda atada al recurso.
- **Ventana: 2 horas**, no los ±5 min del resto del API: el `<video>` fija la URL una vez y
  cada seek reusa el mismo `ts`.
- Hay que mandar `ts` **y** `sig`; si falta alguno, cae al HMAC de cabeceras.

**Errores**: `401` `URL de media expirada` | `Firma de URL de media inválida`.

| Caso | Vía |
|---|---|
| Thumbnails, descargas programáticas, app móvil | HMAC en cabeceras |
| URL que se entrega a un `<video>` o a un `<img src>` | Firma en la query |

---

## 10. Conflictos

**No hay `409` de segmento.** El backend no arbitra: el conflicto se evita por propiedad del
dato según el `estado`, y lo resuelve la app al descargar.

| Estado | Propietario | Regla en la app al descargar |
|---|---|---|
| `propuesta` | backend | Si el local está en otro estado → "hay datos pendientes por enviar al servidor". Si el local también está en `propuesta` → se machaca con lo del backend. |
| `validada` | backend | Misma regla. |
| `contratista`, `ejecucion` | app | Locales, pendientes de enviar. El backend no los sirve. |
| `finalizada` | backend | Solo en backend. Sin conflicto posible. |
