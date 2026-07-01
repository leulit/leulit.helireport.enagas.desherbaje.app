# Contrato backend — Subida de vídeos (TUS-like resumable)

> Versión: 3.0 — 2026-06-27
> Autor: equipo Leulit / Helireport
> Referencia: protocolo TUS-like propio de Enagas (ver sección "Diferencias con tus.io")
>
> **Este documento refleja la implementación real del cliente** (`VideoRemoteAdapter`,
> `NetworkService`). Los nombres de campo son los que el cliente envía y lee:
> **camelCase**, no snake_case.

---

## Contexto

App de campo captura vídeos con la grabadora nativa del SO:
- **Android** graba `.mp4` (`video/mp4`)
- **iOS** graba `.mov` (`video/quicktime`, H.264/AAC)

Vídeos pueden ser grandes (hasta ~3 min, ~500 MB en campo). La subida es **TUS-like resumable**: si la red se corta a mitad, el siguiente drain retoma desde el último byte confirmado.

El backend realiza el remux `.mov→.mp4` si `mimeType == video/quicktime` (ffmpeg -c copy, sin recodificación, instantáneo).

---

## Autenticación — Esquema exclusivo para rutas de vídeo

> **Importante:** Las rutas de vídeo usan un esquema HMAC **distinto** al del resto de la app. NO llevan `Authorization: Bearer`. NO usan los headers `x-flutter-*`.

| Header | Formato |
|---|---|
| `X-HMAC-Signature` | HMAC-SHA256 hexadecimal lowercase del payload |
| `X-Timestamp` | Timestamp en **milisegundos** Unix (no segundos) |

**Payload firmado:**
```
{timestampMs}:{METHOD_UPPERCASE}:{path_relativo}
```

Ejemplo para `PATCH /api/enagas/v1/videos/upload/abc123`:
```
1750941234567:PATCH:/api/enagas/v1/videos/upload/abc123
```

**Ventana anti-replay:** ±5 minutos. Si el server recibe un timestamp fuera de ventana devuelve 401/403.

**Generación en cliente:** `ApiSecurityService.buildEnagasVideoHeaders(method, path)` — fresco en cada llamada (incluyendo reintentos de chunk, para que el timestamp siempre esté dentro de la ventana).

**Diferencia con esquema legacy** (`x-flutter-*`):

| Característica | Legacy (resto de endpoints) | Vídeo |
|---|---|---|
| Timestamp | Segundos | **Milisegundos** |
| Nonce | Sí (`x-flutter-nonce`) | **No** |
| Header firma | `x-flutter-signature` | `X-HMAC-Signature` |
| Header tiempo | `x-flutter-timestamp` | `X-Timestamp` |
| Bearer token | Sí (si hay sesión) | **No** |

---

## Endpoints

### 1. Init — `POST /api/enagas/v1/videos/upload`

Inicia una nueva sesión de subida. Devuelve un `uploadId` opaco (UUID del servidor) que identifica la sesión en todos los pasos siguientes.

#### Headers

```
X-HMAC-Signature: {firma}
X-Timestamp: {ms}
Content-Type: application/json
```

#### Body

```json
{
  "clientId": "550e8400-e29b-41d4-a716-446655440000",
  "segmentoId": 42,
  "originalFilename": "video.mp4",
  "mimeType": "video/mp4",
  "totalBytes": 20971520,
  "usuariologged": "operario01",
  "idusuariologged": 7
}
```

| Campo | Tipo | Descripción |
|---|---|---|
| `clientId` | `string` UUID | ID del cliente. Clave de idempotencia: re-init con mismo `clientId` reutiliza sesión existente si incompleta |
| `segmentoId` | `int` | ID remoto del segmento |
| `originalFilename` | `string` | Nombre del fichero original |
| `mimeType` | `string` | `"video/mp4"` o `"video/quicktime"` |
| `totalBytes` | `int` | Tamaño total del fichero en bytes |
| `usuariologged` | `string` | Usuario en sesión (de `SharedPreferences`, `""` si ausente) |
| `idusuariologged` | `int` | ID de usuario en sesión (`0` si ausente) |

> El cliente **no** envía `tipo_video` ni `actividad_id` en el Init.

#### Respuesta 201

```json
{ "uploadId": "server-uuid-abc", "offset": 0, "segmentoId": 42 }
```

| Campo | Tipo | Descripción |
|---|---|---|
| `uploadId` | `string` | UUID opaco del servidor. **Obligatorio** — si falta o es vacío, el cliente trata la subida como `SyncUnrecoverable` |
| `offset` | `int` | Offset inicial confirmado (normalmente `0`; reanuda si la sesión ya existía) |
| `segmentoId` | `int` | Eco del segmento (informativo) |

El cliente persiste `uploadId` en SQLite (`video_segmento_entity.uploadId`) inmediatamente tras recibir esta respuesta. Este valor se usa en todos los pasos siguientes.

---

### 2. Chunk — `PATCH /api/enagas/v1/videos/upload/{uploadId}`

Sube un fragmento del fichero. Llamado sucesivamente hasta completar.

#### Headers

```
X-HMAC-Signature: {firma}
X-Timestamp: {ms}
Content-Type: application/octet-stream
Upload-Offset: {offset}
```

- `Upload-Offset`: posición en bytes donde empieza este chunk (0-indexed). Primer chunk = 0.

#### Body

Bytes crudos del chunk. Tamaño por defecto: 5 MB. El último chunk puede ser menor.

#### Respuesta 200

```json
{ "offset": 5242880 }
```

- `offset`: próximo offset esperado (= bytes confirmados acumulados). El cliente usa este valor como `Upload-Offset` del siguiente chunk.

> El cliente determina el fin de la subida comparando `offset >= totalBytes` localmente; **no** depende de ningún flag `completed` en la respuesta del chunk. Tras el último chunk llama explícitamente a **Complete** (paso 4). Si el servidor incluye campos extra (`complete`, `download_url`, …) el cliente los ignora en este paso.

---

### 3. Status — `GET /api/enagas/v1/videos/upload/{uploadId}`

Consulta el estado de una sesión de subida. Permite que el cliente determine desde qué offset reanudar.

#### Headers

```
X-HMAC-Signature: {firma}
X-Timestamp: {ms}
```

El cliente lee dos campos: `offset` (int) y `complete` (bool).

#### Respuesta 200 — sesión en curso

```json
{
  "uploadId": "server-uuid-abc",
  "offset": 10485760,
  "totalBytes": 20971520,
  "mimeType": "video/mp4",
  "originalFilename": "video.mp4",
  "complete": false
}
```

#### Respuesta 200 — sesión completada

```json
{
  "uploadId": "server-uuid-abc",
  "offset": 20971520,
  "complete": true
}
```

Si `complete == true`, el cliente trata la subida como éxito idempotente (`SyncSuccess`) sin reenviar chunks.

#### Respuesta 404 — sesión no encontrada

```json
{ "error": "Sesión de subida no encontrada" }
```

Si el servidor devuelve 404, el cliente re-inicia la subida (nueva llamada a Init) desde el byte 0.

---

### 4. Complete — `POST /api/enagas/v1/videos/upload/{uploadId}/complete`

Finaliza la sesión. Confirma al backend que todos los chunks han sido enviados y dispara el ensamblado/remux.

#### Headers

```
X-HMAC-Signature: {firma}
X-Timestamp: {ms}
Content-Type: application/json
```

#### Body

Vacío. El cliente envía `POST` sin cuerpo (solo headers HMAC + `Content-Type: application/json`).

#### Respuesta 200

```json
{ "uploadId": "server-uuid-abc", "status": "recibido" }
```

Confirmación de subida completada. El `remoteId` del cliente se establece como `uploadId`. El cliente **no** lee el cuerpo de esta respuesta (solo le importa el `2xx`); construye la `url` de descarga localmente vía `ApiEndpoints.videoDownload(uploadId)`.

---

### 5. Download — `GET /api/enagas/v1/videos/download/{uploadId}.mp4`

URL de descarga del vídeo final (ya remuxado si era `.mov`). Solo para lectura/preview. No se usa durante el proceso de subida.

---

## Flujo de estado — máquina del adapter

```
[entity.uploadId == null]
         │
         ▼
      INIT → persiste uploadId en SQLite
         │
         ▼
[entity.uploadId != null] → GET status
         │
         ├── 404  → re-INIT (sesión expiró en servidor)
         │
         ├── complete=true → SyncSuccess (ya subido, idempotente)
         │
         └── offset=N → chunk loop desde N
                  │
                  ▼
               PATCH chunk[N → N+5MB] → resp { offset }
                  │
                  ├── retryable (offline/timeout/5xx) → retry max 3
                  │       └── antes de retry: re-GET status para sync offset
                  │
                  ├── offset >= totalBytes → COMPLETE → SyncSuccess
                  │
                  └── siguiente chunk → …
```

---

## Mapeo de errores → comportamiento cliente

| HTTP | Categoría | Comportamiento |
|---|---|---|
| 200–299 | — | `SyncSuccess` |
| 408, 429, 5xx | retryable | `SyncRetryable` — outbox reintenta, reanuda desde offset guardado |
| **401, 403** | **HMAC failure** | **`SyncUnrecoverable` — NO `AuthExpiredException`, NO logout**. La firma fue rechazada; el operario debe revisar la sesión |
| 400, 404, 422 | unrecoverable | `SyncUnrecoverable` — job marcado muerto, se muestra al operario |
| Timeout / sin red | offline/timeout | `SyncRetryable` |

> **Regla crítica:** 401/403 en rutas de vídeo = fallo HMAC, NO expiración de token de sesión. El adapter maneja `NetworkErrorCategory.unauthorized` → `SyncUnrecoverable`, bypaseando `syncOutcomeFromNetworkError` (que lanzaría `AuthExpiredException`).

---

## Notas de implementación cliente

- **Tamaño de chunk**: 5 MB (constante en `VideoRemoteAdapter._chunkSize`).
- **Timeout por chunk**: 4 minutos (`_videoDio` en `NetworkService`). Tolera redes 3G lentas en campo. Este timeout también cubre la ventana HMAC de ±5 min.
- **`uploadId` persistencia**: guardado vía `VideoLocalStore.saveUploadId(clientId, uploadId)` justo tras el Init. Sobrevive a crash/reinicio. `remoteId` getter de la entidad retorna `uploadId ?? id?.toString()`.
- **Retry por chunk**: max 3 intentos, solo errores retryable (no unrecoverable). Backoff: 200ms × intento. Antes de cada retry se re-consulta el status para sincronizar el offset.
- **Re-init por 404**: si el servidor responde 404 en GET status (sesión expirada), el adapter hace un nuevo Init y reanuda desde 0.
- **Idempotencia Init**: re-init con el mismo `clientId` reutiliza la sesión en curso si existe. No duplica el vídeo.
- **`_videoDio` separado**: instancia Dio sin interceptor HMAC legacy ni retry automático. La firma se aplica manualmente por llamada en `NetworkService`. El adapter NO conoce Dio ni construye HMAC directamente — siempre a través de la facade `NetworkService`.

---

## Diferencias con tus.io estándar

El protocolo de Enagas es un subconjunto TUS-like, no una implementación tus.io completa:

| Característica | tus.io | Este protocolo |
|---|---|---|
| Init | `POST` + respuesta con URL en `Location` header | `POST` + body `{ uploadId, offset }` (201) |
| Chunk | `PATCH` + `Tus-Resumable` header | `PATCH` + `Upload-Offset` header (sin `Tus-Resumable`) |
| Auth | Configurable | HMAC propio (`X-HMAC-Signature`/`X-Timestamp` ms) |
| Complete | Implícito (último chunk) | Explícito: `POST .../complete` separado |
| Fetch libs | `@tus/server`, `tuspy` | No aplica — protocolo propio |

---

## Lógica backend esperada

Al recibir el `POST .../complete`:

1. **Verificar** todos los chunks recibidos (offset total == `totalBytes`).
2. **Ensamblar** los trozos en orden de offset.
3. **Remux opcional**: si `mimeType == video/quicktime`, ejecutar `ffmpeg -i input.mov -c copy output.mp4` (sin recodificación).
4. **Persistir** el `.mp4` final, accesible en `GET /api/enagas/v1/videos/download/{uploadId}.mp4`.
5. **Devolver** `{ uploadId, status: "recibido" }`.
6. **Limpiar** chunks temporales.
