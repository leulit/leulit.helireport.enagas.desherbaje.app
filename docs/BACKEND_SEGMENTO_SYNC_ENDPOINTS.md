# Contrato backend — Sincronización de un segmento (subida + finalización)

> Documento para alinear con el equipo backend. Describe **qué envía la app** al
> subir un segmento y sus hijos, y define el **nuevo endpoint `sync-complete`**
> que informa al backend de que un segmento se ha subido **por completo**.
>
> Base: `AppConfig.apiBaseUrl` = `https://enagastool.helireport.com/api/enagas/v1`.
> Todos los paths son relativos a esa base.

---

## Modelo de sincronización (contexto)

- La app es **offline-first**: la UI siempre lee de SQLite local.
- Un segmento vive en local **XOR** en backend, nunca solapado:
  - al **subir** un segmento completo → se **borra de local** (con sus hijos);
  - al **descargar** un segmento que ya está en local con cambios pendientes →
    se marca **conflicto** (no se pisa lo local).
- El envío es **por segmento** (no por tipo). "Enviar todos" = bucle sobre los
  segmentos pendientes; cada uno sube sus hijos y sus datos, y solo si **todo**
  llegó OK se llama a `sync-complete` y se purga de local.
- Identidad universal: cada entidad lleva un **`client_id` (UUID v4)** estable,
  generado en cliente. El `id` entero del backend es nulo hasta la primera subida.
- **Requisito transversal:** todos los endpoints deben ser **idempotentes por
  `client_id`** (reintento del mismo `client_id` = no-op, devuelve la fila
  existente). Y al **descargar** un segmento, sus hijos embebidos
  (`imagenes[]`, `mensajes[]`) deben devolver **su `client_id`** para que la app
  deduplique local↔nube.

Orden de subida por segmento: **vídeos → fotos → mensajes → datos del segmento →
`sync-complete`**.

> **Identificadores en TODA llamada.** Cada petición de subida/finalización
> incluye los 4 identificadores en **snake_case**: **`client_id`, `segmento_id`,
> `usuariologged`, `idusuariologged`**. `usuariologged` (String) e
> `idusuariologged` (int) se leen de SharedPreferences (`user_usuario` / `user_id`).
>
> **Errores por body, no por status HTTP.** Todas las llamadas son POST o GET y
> responden **200 OK** a nivel HTTP. Es el **cuerpo** de la respuesta el que
> indica si el proceso fue correcto o falló (p. ej. `{ "ok": false, "error": "…" }`).
> No se usan 4xx/409 para errores de negocio.

---

## Autenticación

Dos esquemas conviven (ya en producción):

| Endpoints | Firma |
|---|---|
| segmento, imagen, mensaje, **sync-complete** | **HMAC-SHA256** (interceptor) **+** header `Authorization: Bearer <token>` |
| vídeo (init/chunk/complete) | **HMAC-SHA256 únicamente** (sin Bearer) |

- HMAC: header `X-HMAC-Signature` (hex) + `X-Timestamp` (**ms**). Payload firmado:
  `"{timestampMs}:{METHOD}:{path}"`, `path` relativo con querystring. Ventana ±5 min.
- En rutas HMAC-only (vídeo), **401/403 = firma rechazada**, NO expiración de sesión.

---

## 1. Datos del segmento — `POST /segmentos/update/{id}`

Actualiza los campos editables en campo. Hoy solo se soporta **update** (el
`{id}` es el id remoto; el segmento ya existe en backend porque se descargó).

**Body JSON**
```json
{
  "client_id": "uuid-del-segmento",
  "segmento_id": 123,
  "usuariologged": "usuario",
  "idusuariologged": 45,
  "estado": "En ejecución",
  "lat_inicio": 40.41,   // opcional
  "lng_inicio": -3.70,   // opcional
  "lat_fin": 40.42,      // opcional
  "lng_fin": -3.69,      // opcional
  "ubicacion_gis": { "...": "GeoJSON LineString" }  // opcional
}
```
**Respuesta:** `200 OK`; el body indica éxito o error.

---

## 2. Fotos — `POST /operador/additem` (multipart)

Contrato legacy. Solo **create**. El backend asigna el id remoto y la `url`.

**Campos (multipart/form-data)**
```
file                → binario de la imagen (JPEG/PNG/…)
fileNameOriginal    → nombre original
description         → "Antes del trabajo" | "Después del trabajo"
tipo                → "imagen"
tipovigilancia      → "VH"
usuariologged       → usuario (SharedPreferences)
idusuariologged     → id usuario
client_id           → UUID de la imagen
actividad_id        → id actividad
segmento_id         → id remoto del segmento
tipo_foto           → "antes" | "despues"
```
**Respuesta:** `2xx` con `{ id, url }` (id remoto entero + URL servida).
**Recomendado (FK por client_id):** aceptar/eco de `segmento_client_id`.

---

## 3. Mensajes — `POST /segmentos/mensajes/{segmentoId}`

Solo **create** (no update/delete de mensajes existentes).

**Body JSON**
```json
{
  "client_id": "uuid-del-mensaje",
  "segmento_id": 123,
  "usuariologged": "usuario",
  "idusuariologged": 45,
  "segmento_client_id": "uuid-del-segmento",   // recomendado (FK por client_id)
  "mensaje": "texto",
  "enviado_por": 45
}
```
**Respuesta:** `2xx`. Idealmente eco de `{ id, client_id, ... }`.
**Al descargar** el segmento, `mensajes[]` debe incluir el `client_id` de cada
mensaje (si no, la app no puede deduplicar y aparecerían duplicados).

---

## 4. Vídeos — subida resumible (TUS-like, 3 pasos)

Solo **create**. HMAC-only (sin Bearer). Conversión MOV→MP4 **asíncrona** en backend.

**4.1 Init** — `POST /videos/upload`
```json
{
  "original_filename": "VID_0001.mov",
  "total_bytes": 10485760,
  "mime_type": "video/quicktime",
  "client_id": "uuid-del-video",
  "segmento_id": 123,
  "usuariologged": "usuario",
  "idusuariologged": 45
}
```
→ `201 { "upload_id": "...", "offset": 0, "segmento_id": 123 }`

**4.2 Estado** — `GET /videos/upload/{uploadId}`
→ `200 { uploadId, offset, totalBytes, mimeType, originalFilename, complete }`

**4.3 Chunk** — `PATCH /videos/upload/{uploadId}`
- Header `Upload-Offset: <bytesYaEnServidor>`
- Body = **bytes raw** (chunks de 5 MB)
→ `200 { "offset": <nuevoOffset> }`

**4.4 Complete** — `POST /videos/upload/{uploadId}/complete`
→ `200 { "uploadId": "...", "status": "recibido" }` (dispara MOV→MP4 async)

**Descarga** (referencia, exenta de HMAC): `GET /videos/download/{uploadId}.mp4`
**Recomendado:** re-init con el mismo `clientId` reutiliza la sesión en curso
(idempotencia de sesión).

---

## 5. ⭐ NUEVO — Envío finalizado · `POST /segmentos/{id}/sync-complete`

**Propósito.** La app sube los hijos y los datos del segmento en **peticiones
independientes** (secciones 1-4). El backend nunca sabe "esta fue la última
pieza". Este endpoint es la señal explícita de que **TODO el contenido de un
segmento (datos + fotos + vídeos + mensajes) se ha subido correctamente**.

**Cuándo lo llama la app.** Solo cuando, para ese segmento, **ningún** hijo ni el
propio segmento tiene ya nada pendiente de subir. Inmediatamente después de un
`2xx`, la app **borra el segmento y sus hijos de la base de datos local**.

**Petición**
```
POST /segmentos/{id}/sync-complete
Authorization: Bearer <token>          + firma HMAC
Content-Type: application/json

{
  "client_id": "uuid-del-segmento",
  "segmento_id": 123,
  "usuariologged": "usuario",
  "idusuariologged": 45
}
```

**Respuesta esperada:** `200 OK` (cuerpo libre; basta el status).

**Requisitos backend (críticos):**
1. **Idempotente.** Una segunda llamada para un segmento ya finalizado debe
   devolver `2xx` (no-op). Motivo: si la app cae entre el `sync-complete` y el
   borrado local, reintentará; no debe fallar.
2. **No destructivo.** No borra nada en backend; solo marca el segmento como
   "recepción completa" (o dispara el proceso downstream que corresponda:
   visibilidad para otros usuarios, generación de informe, etc.).
3. **Error → la app NO purga.** HTTP `200` siempre; si el **body** indica error
   (o hay error de red), el segmento y sus hijos quedan intactos en local y se
   reintenta en el próximo envío. El body OK confirma la finalización.

**Pregunta abierta para backend:** ¿necesitáis realmente esta señal (¿gateáis
visibilidad / proceso posterior en la completitud del segmento?), o el modelo
idempotente por `client_id` os basta y el segmento "vale lo que haya llegado"?
Si no la necesitáis, la app puede omitir la llamada y purgar tras drenar su
outbox local.

---

## Resumen de requisitos backend pendientes

| # | Requisito | Afecta a |
|---|---|---|
| R1 | Idempotencia por `client_id` (reintento = no-op) | todos |
| R2 | Eco de `client_id` en hijos embebidos al **descargar** el segmento (`imagenes[]`, `mensajes[]`) | dedup local↔nube |
| R3 | Aceptar `segmento_client_id` en fotos y mensajes (FK por client_id) | fotos, mensajes |
| R4 | Implementar `POST /segmentos/{id}/sync-complete` idempotente | finalización |
| R5 | Errores por **body** (HTTP siempre `200`; `{ok, error}`), nunca 4xx/409 | todos |
