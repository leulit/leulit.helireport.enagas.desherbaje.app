> **ARCHIVADO 2026-08-19.** Superado por `docs/BACKEND_SEGMENTO_SYNC_ENDPOINTS.md` (fuente
> única y vigente). Incorrecto en al menos: `sync-complete` (§"POST /segmentos/{id}/sync-complete")
> dice que el body lleva `{ "client_id": "…" }` — el `NetworkService` real manda `{}` sin body
> para no disparar `FST_ERR_CTP_EMPTY_JSON_BODY`, el `client_id` no viaja ahí.

# Backend spec — segmentos + hijos (desherbaje)

Base URL: `https://<host>/api/enagas/v1` · Auth: HMAC en todos los endpoints.

## HMAC
- Payload firmado: `"{timestampMs}:{METHOD}:{path}"`.
- `path` = ruta relativa **con querystring**, prefijo `/api/enagas/v1` incluido. Sin re-encodear, sin reordenar params, comas literales.
- `timestamp` en ms, ventana ±5 min. `401`/`403` = firma inválida.

## Identidad hijos (imagen/vídeo/mensaje) — por `id` entero
- Payload lleva `id`: `0`/`null`/ausente → INSERT; `>0` → UPDATE.
- Responder con la entidad completa incluyendo su `id` definitivo.
- `client_id` no es clave; no obligatorio devolverlo.

---

## POST /segmentos/upsert
Body JSON. `id`: `0`/null=insert, `>0`=update.
```json
{ "id": 0, "estado": "propuesta", "lat_inicio": 0.0, "lng_inicio": 0.0,
  "lat_fin": 0.0, "lng_fin": 0.0, "ubicacion_gis": "…GeoJSON…" }
```
Response `200`: entidad completa con `id`.

## POST /segmentos/{segmentoId}/imagenes
`multipart/form-data`.

| Campo | Oblig. | Valor |
|---|---|---|
| `file` | sí | binario |
| `id` | sí | `0`=insert, `>0`=update |
| `tipoFoto` | sí | `antes` \| `despues` |
| `capturada_at` | no | ISO8601 |
| `subida_por` | no | usuario |

Response `200`: `{ "id": 123, "url": "…" }`. Errores: `400` (falta file/tipoFoto inválido), `404` (segmento no existe).

## POST /segmentos/mensajes/{segmentoId}
Body JSON. `segmento_id` del body se ignora (manda el path).
```json
{ "id": 0, "mensaje": "texto", "enviado_por": "…" }
```
Response `200`: `{ "id": 55, "mensaje": "…", "enviado_por": "…" }`.

## Vídeo (subida resumable)
- `POST /videos/upload` — init. Body JSON **camelCase**:
  ```json
  { "id": 0, "originalFilename": "IMG.MOV", "totalBytes": 18432000,
    "mimeType": "video/quicktime", "segmentoId": 42,
    "usuariologged": "…", "idusuariologged": 7 }
  ```
  Response `201`: `{ "uploadId": "…", "offset": 0, "segmentoId": 42 }`.
- `POST /videos/upload/{uploadId}` — chunk. **POST** (no PATCH → 404). Header `Upload-Offset: <bytes>`, body `application/octet-stream`. Response `200`: `{ "offset": <n> }`.
- `GET /videos/upload/{uploadId}` — estado. Response `200`: `{ "uploadId", "offset", "totalBytes", "mimeType", "originalFilename", "complete" }`.
- `POST /videos/upload/{uploadId}/complete` — cierre. Response `200`: `{ "uploadId": "…", "id": 987, "status": "recibido" }`. **`id` = id entero del registro de vídeo** (mismo `id` que su fila en `imagenes[]` de la descarga).
- `GET /videos/download/{uploadId}.mp4` — descarga. **Exenta de HMAC.** `404` si la conversión no ha terminado.

## POST /segmentos/{id}/sync-complete
Body: `{ "client_id": "…" }`. Response `200`. Idempotente, no destructivo. Marca el segmento como completamente enviado; el segmento no se sirve a otros clientes hasta esta llamada.

## GET /segmentos/contratista?cts=CT1,CT2
- `cts`: CSV de **nombres** de CT, URL-encoded, comas literales. Opcional → todos los del usuario.
- Response `200`: array de segmentos en estado `propuesta` + `validada`, cada uno con `imagenes[]` y `mensajes[]`.
- Cada hijo con su `id` entero. Vídeos = filas de `imagenes[]` con `mime_type` `video/*` y `url` `.mp4` (no array `videos[]` aparte).
```jsonc
[
  { "id": 42, "estado": "propuesta", "nombre": "…", "ctname": "…",
    "imagenes": [
      { "id": 123, "url": "…/segmentos/imagen/123", "tipo_foto": "antes",   "mime_type": "image/jpeg" },
      { "id": 987, "url": "…/videos/download/<uploadId>.mp4", "tipo_foto": "despues", "mime_type": "video/mp4" }
    ],
    "mensajes": [ { "id": 55, "mensaje": "texto", "enviado_por": "…" } ] }
]
```

## Conflictos
Sin `409`. Solo se sirven `propuesta`/`validada`; el resto de estados los posee el cliente.
