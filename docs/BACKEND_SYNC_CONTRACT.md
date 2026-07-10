# Contrato de sincronización — Backend Helireport / Enagastool

> Documento técnico para el equipo de backend.
> Especifica los requisitos que el cliente móvil (`leulit_helireport_enagas_desherbaje_app`) necesita del backend para implementar sincronización offline-first robusta.

**Versión:** 1.0
**Fecha:** 2026-04-25
**Autor:** Equipo Leulit (mobile)
**Estado:** Pendiente de implementación en backend

---

## 1. Resumen ejecutivo

La app móvil de campo opera **offline-first**: el operador trabaja sin conexión durante toda su jornada y el dispositivo es la fuente operativa de los datos hasta que el usuario decide sincronizar manualmente con el backend.

Para que esa sincronización sea **idempotente, robusta y reanudable**, el backend debe cumplir un conjunto de reglas que se especifican en este documento. Sin ellas, el cliente no puede garantizar que los datos del operador no se dupliquen, no se pierdan, y se reconcilien correctamente.

**Resumen de requisitos del backend:**

1. Idempotencia por `client_id` en todas las entidades sincronizables.
2. Relaciones entre entidades por `client_id`, no por id remoto.
3. Endpoint de pull "full" para entidades descargables.
4. Mensajes de error 4xx legibles en español.
5. Códigos HTTP semánticos consistentes.
6. Endpoint específico `POST /positions/batch` para puntos GPS.
7. Campo `updated_at` ISO8601 UTC en todas las entidades sincronizables.

---

## 2. Modelo de identidad

Cada registro sincronizable existe con dos identificadores:

| Campo | Origen | Inmutabilidad | Uso |
|---|---|---|---|
| `client_id` | Generado por el cliente (UUID v4) | Inmutable durante toda la vida del registro | Clave primaria lógica del dominio. La app lo usa para todo: relaciones, búsquedas, reconciliación. |
| `remote_id` (formato libre del backend) | Asignado por el backend en el primer sync exitoso | Inmutable una vez asignado | Identificador interno del backend. La app lo persiste pero no lo usa como referencia. |

**Reglas:**

- El `client_id` viaja en el payload de **todas** las operaciones del cliente al backend.
- El backend **debe persistir** el `client_id` y consultar por él para detectar duplicados.
- El backend devuelve el `remote_id` en la respuesta del primer sync exitoso. La app lo guarda asociado al `client_id`.
- Si el cliente reenvía el mismo `client_id` (reintento), el backend devuelve el mismo `remote_id` que la primera vez. **Nunca crea un duplicado**.

---

## 3. Idempotencia por `client_id`

**Requisito crítico.** Cualquier operación de creación o actualización debe ser idempotente respecto al `client_id`.

### 3.1 Creación

```http
POST /api/segmentos
Content-Type: application/json

{
  "client_id": "550e8400-e29b-41d4-a716-446655440000",
  "ct_id": 12,
  "nombre": "Segmento PK 12+340",
  "descripcion": "...",
  "estado": "Propuesta",
  "updated_at": "2026-04-25T10:23:45.000Z",
  ...
}
```

**Comportamiento esperado del backend:**

- Si **no existe** un registro con `client_id = "550e8400..."`: crearlo. Asignar `remote_id`. Devolver `201 Created` con el cuerpo completo del recurso (incluyendo `remote_id` y `client_id`).
- Si **ya existe** un registro con `client_id = "550e8400..."`: **NO duplicar**. Devolver el mismo `remote_id` que la primera vez con `200 OK` o `201 Created` (en ambos casos el cliente trata la respuesta como éxito y guarda el `remote_id`).

```http
HTTP/1.1 201 Created
Content-Type: application/json

{
  "client_id": "550e8400-e29b-41d4-a716-446655440000",
  "remote_id": 42891,
  "ct_id": 12,
  "nombre": "Segmento PK 12+340",
  "estado": "Propuesta",
  "updated_at": "2026-04-25T10:23:45.000Z",
  "created_at": "2026-04-25T10:24:01.000Z"
}
```

### 3.2 Actualización

Misma regla. La actualización viaja con el `client_id` y el cuerpo nuevo:

```http
POST /api/segmentos/update
Content-Type: application/json

{
  "client_id": "550e8400-e29b-41d4-a716-446655440000",
  "estado": "Finalizada",
  "updated_at": "2026-04-25T15:11:02.000Z"
}
```

El backend localiza el registro por `client_id` (no por `remote_id`) y aplica la actualización. Devuelve `200 OK` con el recurso actualizado.

> **Nota:** la app puede o no incluir `remote_id` en el cuerpo. El backend debe **localizar siempre por `client_id`** y nunca confiar en el `remote_id` recibido como referencia. El `remote_id` puede usarse para validación adicional pero no como clave de búsqueda.

---

## 4. Relaciones entre entidades por `client_id`

**Requisito crítico para offline.**

Cuando un operador crea offline una imagen asociada a un segmento que también ha creado offline, **ninguna de las dos entidades tiene `remote_id` todavía**. Ambas tienen solo `client_id`. Por tanto, la imagen referencia al segmento mediante `segmento_client_id`, no `segmento_id`.

### 4.1 Ejemplo: subida de imagen referenciando segmento offline

```http
POST /api/imagenes
Content-Type: multipart/form-data

client_id=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
segmento_client_id=550e8400-e29b-41d4-a716-446655440000
tipo_foto=antes
capturada_at=2026-04-25T11:05:30.000Z
gis_json={"type":"FeatureCollection","features":[...]}
file=@imagen.jpg
```

**Reglas del backend:**

1. Resolver `segmento_client_id` a su `remote_id` interno (consulta por `client_id`).
2. Si el segmento no existe aún (orden de subida invertido): **rechazar con 422** con `error_message` claro. La app reordena y reintenta.
3. Una vez resuelto: persistir la imagen con la FK al segmento correcto.
4. Devolver el recurso imagen con su propio `client_id` y `remote_id`.

### 4.2 Orden recomendado del cliente

La app **garantiza** que envía las entidades en orden topológico: primero las que no dependen de nadie, luego las que dependen. Para Segmento → Imagen, primero sube todos los segmentos pendientes, después las imágenes. Esto reduce los 422 por orden.

Pero el backend **no debe asumir orden**: si llega una imagen con `segmento_client_id` desconocido, devuelve 422 explicativo y el cliente reintentará después.

### 4.3 Campo `gis_json` (GeoJSON) en foto y vídeo

**Cambio 2026-07-10.** La media capturada con la cámara de la app viaja georreferenciada en un campo nuevo **`gis_json`** (string GeoJSON). Aplica al payload de **foto** (`POST /api/imagenes`) y de **vídeo** (subida TUS-like — ver `docs/BACKEND_VIDEO_CONTRACT.md`, se envía en el Init).

- Top-level siempre `FeatureCollection`. Orden de coordenadas GeoJSON estándar **`[lon, lat]`** (¡no `[lat, lon]`!).
- **Foto:** geometría `Point` `[lon, lat, alt]`; rumbo y extras (`heading`, `heading_accuracy`, `gps_heading`, `accuracy_m`, `altitude_m`, `speed_mps`, `captured_at`) en `properties` (`kind: "photo"`).
- **Vídeo:** geometría `LineString` con **coordenada custom** `[lon, lat, alt, heading_deg, t_epoch_ms]` por vértice (1 muestra/seg); `properties` lleva `coord_format`, `sample_interval_s`, `started_at`, `ended_at` (`kind: "video"`). Con 1 muestra degrada a `Point`.
- Ambos incluyen en `properties`: `kind`, `user_id`, `os`, `os_version`, `device_model`, `app_version`.
- **`gis_json` puede llegar `null`** (permiso de ubicación denegado, sin fix GPS, o media de galería). El backend debe aceptarlo como opcional y no rechazar el upload por su ausencia.
- El backend puede persistirlo tal cual (columna JSON/text) o indexar la geometría; el cliente no espera transformación.

> **Eliminado del payload de foto y vídeo:** `latitud`, `longitud`, `fixed_latitud`, `fixed_longitud`. Ninguno se poblaba; toda la georreferenciación de captura pasa ahora por `gis_json`.

---

## 5. Endpoints de subida (push)

Patrón general para cualquier entidad con escritura desde cliente:

| Endpoint | Operación | Idempotencia |
|---|---|---|
| `POST /api/<entidad>` | Crear | Por `client_id` |
| `POST /api/<entidad>/update` o `PATCH /api/<entidad>` | Actualizar | Por `client_id` |
| `DELETE /api/<entidad>?client_id=...` | Borrar | Por `client_id` (idempotente: borrar lo ya borrado devuelve 200/204) |

### 5.1 Códigos HTTP esperados

| Código | Significado | Comportamiento del cliente |
|---|---|---|
| `200 OK` / `201 Created` | Éxito | Marca el job como `synced`, guarda `remote_id`. |
| `204 No Content` | Éxito sin cuerpo (típico DELETE) | Marca el job como `synced`. |
| `400 Bad Request` | Petición malformada | Marca el job como `rejected`, muestra `error_message` al operador. |
| `401 Unauthorized` | Token expirado | **Aborta el drain entero**, navega a login. |
| `403 Forbidden` | Sin permisos | Marca el job como `rejected`, muestra `error_message`. |
| `404 Not Found` | Recurso o ruta inexistente | Marca el job como `rejected`. |
| `408 Request Timeout` | Timeout | Reintenta más tarde (manual). |
| `409 Conflict` | Conflicto de versión | Devuelve la versión servidor (ver §7). |
| `422 Unprocessable Entity` | Validación fallida | Marca el job como `rejected`, muestra `error_message` al operador. |
| `429 Too Many Requests` | Throttling | Reintenta más tarde (manual). |
| `5xx` | Error servidor | Reintenta más tarde (manual). |

### 5.2 Errores 4xx legibles en español (requisito crítico)

Cualquier respuesta 4xx (especialmente 422 y 400) debe llevar un campo `error_message` con texto humano comprensible para un operador no técnico:

```http
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/json

{
  "error_message": "Falta la fecha de inicio del segmento.",
  "error_code": "VALIDATION_FECHA_INICIO_REQUIRED",
  "field": "fecha_inicio"
}
```

| Aceptable | Inaceptable |
|---|---|
| *"Falta la fecha de inicio del segmento."* | `"VALIDATION_ERROR_FIELD_NULL"` |
| *"El estado 'Finalizada' requiere foto previa y posterior."* | `"FSMException: invalid transition Propuesta→Finalizada"` |
| *"La imagen excede el tamaño máximo de 10 MB."* | `"FileSizeException at line 234"` |
| *"El segmento referenciado no existe en el sistema."* | `"FK_CONSTRAINT_VIOLATION"` |

`error_code` y `field` son opcionales — útiles para localización futura y para que el cliente navegue automáticamente al campo relevante. Pero el `error_message` es obligatorio y debe ser presentable directamente al operador.

---

## 6. Endpoints de descarga (pull)

Solo se implementan en entidades **explícitamente pulleables** (declaradas como tal por el cliente). El cliente NO descarga datos del backend salvo cuando el operador lo pide explícitamente desde la pantalla de sincronización.

### 6.1 Modelo "full pull"

El cliente pide **todo** el conjunto aplicable al operador. **No** se usa delta (`?since=`) ni cursores. Razones:

- Simplifica el backend (sin tracking de versiones por cliente).
- Simplifica el cliente (sin estado intermedio).
- El operador descarga al inicio de su jornada (oficina con wifi). El volumen es manejable.

**Patrón general:**

```http
GET /api/<entidad>?<filtros-de-operador>
Authorization: HMAC ...

[
  { "client_id": "...", "remote_id": ..., "updated_at": "...", ... },
  { "client_id": "...", "remote_id": ..., "updated_at": "...", ... },
  ...
]
```

**Filtros recomendados** (ejemplos): `?operador=12`, `?ct_id=42`. La lista exacta de filtros es responsabilidad del backend según el modelo de autorización del operador.

### 6.2 Requisitos del payload de pull

Cada elemento del array debe incluir:

- `client_id` (si la entidad fue creada originariamente por un cliente).
- `remote_id`.
- `updated_at` ISO8601 UTC.
- Resto de campos del recurso.

**Si una entidad fue creada exclusivamente desde el backend** (ej. master data como `Gasoducto`, `PK`), el `client_id` puede ser generado y persistido por el backend la primera vez. Lo importante es que sea estable a través de pulls — no debe cambiar entre llamadas.

### 6.3 Resolución de conflictos en el cliente

El cliente compara `updated_at` local vs remoto. Si el local es más nuevo, o hay outbox pendiente para ese `client_id`, marca el registro como **conflicto** y pregunta al operador. El backend no participa en esta decisión, solo proporciona la versión actual.

---

## 7. Conflicto (HTTP 409) en push

Caso: el cliente intenta actualizar un registro que ha cambiado en backend desde la última sync local.

**Detección:** el cliente envía `updated_at` local; si difiere de la versión que el backend tiene, responde 409.

```http
HTTP/1.1 409 Conflict
Content-Type: application/json

{
  "error_message": "Este segmento ha sido modificado en oficina mientras estaba offline.",
  "server_version": {
    "client_id": "550e8400-e29b-41d4-a716-446655440000",
    "remote_id": 42891,
    "estado": "Validada",
    "updated_at": "2026-04-25T14:50:11.000Z",
    ...
  }
}
```

El `server_version` debe ser el recurso completo, listo para que el cliente lo presente en la UI de resolución de conflictos.

> **Nota:** este caso es raro porque el cliente normalmente hace pull antes de push (en "Preparar trabajo de campo"). Pero puede ocurrir si dos operadores trabajan el mismo registro simultáneamente.

---

## 8. Endpoint específico: subida de posiciones GPS

**Caso especial.** Las posiciones GPS se acumulan en lotes de hasta 500 puntos. Cada lote es UN job del cliente y produce UN POST.

```http
POST /api/positions/batch
Content-Type: application/json

{
  "batch_client_id": "f1e2d3c4-b5a6-9788-0192-3456789abcde",
  "operador_id": 12,
  "device_id": "android-pixel7-abc123",
  "started_at": "2026-04-25T08:30:00.000Z",
  "ended_at":   "2026-04-25T09:00:00.000Z",
  "points": [
    {
      "captured_at": "2026-04-25T08:30:00.000Z",
      "lat": 40.412345,
      "lng": -3.701234,
      "accuracy_m": 5.2,
      "altitude_m": 678.4,
      "speed_mps": 1.2
    },
    {
      "captured_at": "2026-04-25T08:30:01.000Z",
      "lat": 40.412350,
      "lng": -3.701231,
      "accuracy_m": 5.0,
      ...
    }
    // ... hasta 500 puntos
  ]
}
```

**Reglas del backend:**

- Idempotencia por `batch_client_id`. Reenviar el mismo batch no duplica puntos.
- Persistencia ordenada por `captured_at` ascendente.
- Validación: timestamps coherentes, lat/lng en rango válido. Devolver 422 si no.
- Volumen previsto: una jornada de 8h × 1Hz = ~28.800 puntos = ~58 batches. Multiplicar por número de operadores activos para dimensionar.

**Respuesta esperada:**

```http
HTTP/1.1 201 Created

{
  "batch_client_id": "f1e2d3c4-b5a6-9788-0192-3456789abcde",
  "remote_id": 1234,
  "points_accepted": 500,
  "points_rejected": 0
}
```

Si algunos puntos individuales se rechazan por validación, devolver 207 (Multi-Status) o un campo `points_rejected` con detalle. El cliente acepta éxito parcial.

---

## 9. Campo `updated_at`

**Requisito crítico para conflict resolution.**

Toda entidad sincronizable debe tener un campo `updated_at` ISO8601 UTC que el backend mantiene actualizado en cada cambio del registro.

**Reglas:**

- Formato exacto: `2026-04-25T14:50:11.000Z` (con milisegundos, zona Z).
- Solo el backend puede modificarlo. La app envía su propio `updated_at` local pero el backend lo sustituye por el suyo en la respuesta.
- En conflictos (409), se usa para mostrar al operador "esta versión del servidor es más nueva que la tuya por X minutos".

---

## 10. Autenticación

El cliente usa autenticación HMAC sobre cada petición (sistema actual del proyecto). El token de usuario viaja como header.

**Comportamiento ante token expirado (401):**

El cliente, al recibir 401 durante un drain o pull:
1. Aborta inmediatamente el flujo en curso.
2. Navega forzosamente al login.
3. Una vez re-autenticado, el operador puede pulsar "Subir todo" otra vez. Los pendientes siguen ahí (no se han perdido).

**No hay refresh token.** El backend no necesita implementar refresh; cuando expira el token, el flujo es login completo.

---

## 11. Lista resumida de entregables del backend

Para que la app cliente sea funcional con la nueva arquitectura, el backend debe:

- [ ] Soportar `client_id` UUID v4 en todas las entidades sincronizables.
- [ ] Implementar idempotencia por `client_id` en POST de creación y actualización.
- [ ] Aceptar relaciones entre entidades por `client_id` (no `remote_id`).
- [ ] Mantener campo `updated_at` ISO8601 UTC en todas las entidades sincronizables.
- [ ] Implementar endpoint GET de full pull para entidades descargables (a definir cuáles entre cliente y producto).
- [ ] Devolver `error_message` legible en español en todas las respuestas 4xx.
- [ ] Aplicar códigos HTTP semánticos según §5.1.
- [ ] Devolver `server_version` completa en 409.
- [ ] Implementar `POST /api/positions/batch` con idempotencia por `batch_client_id`.

---

## 12. Endpoints específicos pendientes para offline-first completo

A medida que las entidades del dominio se migran al motor de sincronización, dos quedan pendientes de un endpoint de pull adecuado:

### 12.1 `GET /mensajes?operador=<id>` — pull global de mensajes

**Estado actual:** el cliente lee mensajes con `GET /segmentos/mensajes/{segmentoId}` (filtrado por segmento). Esto funciona online pero **no encaja** con el contrato `RemoteFetcher.pullAll()` del motor (que es sin parámetros, full pull).

**Necesario:** un endpoint que devuelva **todos los mensajes que el operador puede ver** en un único array, con la misma forma que el actual por segmento. Idealmente:

```http
GET /api/mensajes?operador=12
```

devuelve un array de mensajes con `client_id`, `id`, `segmento_id`, `mensaje`, `enviado_por`, `created_at`, `updated_at`. El cliente filtrará por `segmento_id` localmente.

**Hasta entonces:** el cliente sólo migra la **escritura** (`POST /segmentos/mensajes/{segmentoId}/add`) al motor; las lecturas siguen siendo online por segmento, con merge de pendientes locales y fallback a caché local cuando no hay red.

### 12.2 Endpoints REST únicos para `Gasoductos` y `PKs`

**Estado actual:** el cliente descarga gasoductos y puntos kilométricos como **GeoJSON multi-archivo** (un fichero por CT del usuario), descargados en paralelo y procesados por un pipeline interno (`JsonLoaderService`).

**Necesario para integrarlos al motor:** endpoints REST únicos por entidad, paginables:

```http
GET /api/gasoductos?ct_ids=12,15,23
GET /api/pks?ct_ids=12,15,23
```

devuelven todos los registros aplicables al operador en un único array JSON, con el mismo formato que produce hoy el procesador GeoJSON.

**Hasta entonces:** estas dos entidades quedan **fuera del motor**. Su tabla local existe en `local_database.dart` y su servicio (`GasoductosService`, `PksService`) gestiona descarga + caché de forma independiente. No es deuda crítica para offline-first (las trazas no se editan desde el cliente), pero sí impide que la sync page muestre "Datos descargables" de forma genérica para todas las entidades.

---

## 13. Preguntas abiertas / decisiones pendientes

Estas decisiones se cerrarán cuando el equipo de backend revise este documento:

1. **Filtros exactos de los GET de pull**: ¿`?operador=`, `?ct_id=`, ambos, otros?
2. **Tamaño máximo de payload aceptado** en POST (especialmente para `/positions/batch` y subida de imágenes).
3. **Política de retención** de posiciones GPS en backend (¿cuánto tiempo se guardan los puntos?).
4. **Endpoint de revocación** de token (logout server-side) — opcional.
5. **Lista cerrada de entidades pulleables** (gasoductos, pks, segmentos, mensajes... — depende del producto).
6. **Versionado de la API**: ¿`/api/v1/...`? ¿headers `Accept: application/vnd.helireport.v1+json`?

---

## Apéndice A — Glosario rápido

| Término | Definición |
|---|---|
| `client_id` | UUID v4 generado por el cliente. PK lógica del dominio. Inmutable. |
| `remote_id` | Identificador interno del backend. Asignado al primer sync. |
| `batch_client_id` | UUID v4 que identifica un lote de puntos GPS. Usado para idempotencia del endpoint `/positions/batch`. |
| Push | Envío del cliente al backend (creación/actualización/borrado). |
| Pull | Descarga del backend al cliente. Manual y explícita. |
| Drain | Proceso de vaciar el outbox del cliente enviando todos los jobs pendientes al backend. |
| Outbox | Cola local del cliente con operaciones pendientes de subir al backend. |
| Conflicto (409) | Situación donde la versión local y la del servidor han divergido. Lo resuelve el operador. |
| Rechazo (4xx irrecoverable) | Operación que el backend no acepta y reintentar no arregla. El operador debe editar o descartar. |
