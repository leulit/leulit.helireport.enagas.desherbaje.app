> **ARCHIVADO 2026-08-19.** Superado por `docs/BACKEND_SEGMENTO_SYNC_ENDPOINTS.md` (fuente
> única y vigente). Incorrecto en al menos: la afirmación de la línea 4, "la app ya está
> adaptada" al modelo de identidad por `id`, es **falsa** —
> `imagen_remote_adapter.dart:51`, `mensaje_remote_adapter.dart:26` y
> `video_remote_adapter.dart:68` rechazan toda operación que no sea `create` y ninguno envía
> `id` en el payload; el cliente móvil hoy solo hace INSERT de imagen/mensaje/vídeo, el UPDATE
> no está implementado.

# Backend — descarga contratista + identidad de entidades hijas por `id`

> Instrucciones para el equipo backend. App **desherbaje** (Flutter offline-first).
> Fecha: 2026-07-16. La app ya está adaptada; falta implementarlo en el backend.

Dos cosas: (1) el endpoint de descarga para contratista, (2) el modelo de identidad de
las entidades hijas — **por `id` entero, igual que el segmento**, NO por `client_id`.

---

## 1. Modelo de identidad — hijos por `id` (idéntico al segmento)

Imagen, vídeo y mensaje siguen EXACTAMENTE el patrón del segmento (`/segmentos/upsert`):

- El payload lleva el `id` de la entidad hija:
  - `id` = `0` / `null` / ausente → **INSERT**.
  - `id` > 0 → **UPDATE** de esa fila.
- El backend hace insert o update en función de ese `id` y **devuelve la entidad completa**
  con su `id` definitivo.
- El frontend **lee el `id` de la respuesta y lo persiste en local**. A partir de ahí ese hijo
  ya tiene id de servidor.

**Consecuencias (por qué esto basta y `client_id` no hace falta como clave):**

- **Reenvío tras fallo parcial** (p.ej. segmento + fotos + mensajes OK, vídeo falla): al reenviar,
  las entidades ya subidas viajan con su `id` de servidor → el backend hace **UPDATE** (no
  duplica); solo el vídeo se reintenta como insert.
- **Dedup en re-descarga**: se casa local↔nube por `id`. Cuando un hijo puede re-descargarse ya
  tiene `id` en ambos lados (el frontend lo guardó tras subir) → match por `id`, sin duplicar.
- **Visibilidad**: el segmento no se sirve a otros clientes / app de gestión hasta que la app
  llama a `POST /segmentos/{id}/sync-complete`. Un envío a medias no es visible.

`client_id` puede seguir viajando (el segmento lo manda), pero **el backend NO debe usarlo como
clave de identidad ni es obligatorio devolverlo**. La clave es el `id`.

### 1.1 Endpoints de push de hijos (sin cambio de ruta, solo semántica de `id`)

| Entidad | Endpoint | Campo id en payload |
|---|---|---|
| Imagen | `POST /segmentos/{segmentoId}/imagenes` (multipart) | field `id` (`0`=insert) |
| Mensaje | `POST /segmentos/mensajes/{segmentoId}` (JSON) | `id` en body (`0`=insert) |
| Vídeo | init `POST /videos/upload` (JSON) | `id` en body (`0`=insert) |

En los tres: responder con la entidad completa incluyendo su `id` entero definitivo.

### 1.2 Vídeo — devolver el `id` entero del registro en el `complete`

El vídeo tiene dos identificadores: `uploadId` (sesión/descarga, ya existe) y el **`id` entero
del registro de vídeo** (para dedup, igual que foto/mensaje).

- `POST /videos/upload/{uploadId}/complete` debe devolver, además de lo actual, el **`id` entero**
  del registro de vídeo creado/actualizado:
  ```json
  { "uploadId": "…", "id": 987, "status": "recibido" }
  ```
- Ese **mismo `id`** debe ser el que aparezca como `id` de la fila de vídeo dentro de `imagenes[]`
  en la descarga (§2). Así el frontend casa el vídeo local con su fila de nube por `id`.
- El frontend lee ese `id` y lo guarda en local; `uploadId` se conserva aparte para la URL de
  descarga y el resume.

---

## 2. Endpoint de descarga contratista

```
GET /api/enagas/v1/segmentos/contratista?cts=CT1,CT2
```

- Sustituye al uso de `GET /segmentos/bycts/{cts}` (los CTs pasan del path al **querystring**).
- `cts`: **CSV de nombres de CT** (no ctids), cada nombre URL-encoded, **comas literales**.
  Ejemplo real de la app: `?cts=ct-burgos,ct-plasencia`. Opcional: sin él → todos los CTs
  visibles para el usuario.
- Mantener `GET /segmentos/bycts/{cts}` si otro consumidor lo usa; la app ya no lo llama.

### 2.1 HMAC — firmar el querystring

```
payload = "${timestampMs}:GET:/api/enagas/v1/segmentos/contratista?cts=ct-burgos,ct-plasencia"
```
El backend debe verificar la firma sobre el path **incluyendo el querystring** tal cual llega
(sin re-encodear, sin reordenar, comas literales). Firmar solo el path sin `?cts=…` → `401`.
Timestamp en **ms**, ventana ±5 min. `401`/`403` = fallo de firma, nunca sesión.

### 2.2 Respuesta `200`

Array de segmentos en estado **`propuesta`** y **`validada`** (los que el backend "posee" y
sirve, §8 del contrato), con la misma forma que `/segmentos/upsert` **más** sus hijos
enriquecidos, **cada uno con su `id` entero**:

```jsonc
[
  {
    "id": 42,
    "estado": "propuesta",
    "nombre": "…", "ctname": "…",
    // … resto de campos del segmento …

    "imagenes": [
      { "id": 123, "url": "https://…/segmentos/imagen/123",
        "tipo_foto": "antes",   "mime_type": "image/jpeg" },

      // el VÍDEO viaja como fila de imagenes[]; su `id` == el devuelto en complete (§1.2)
      { "id": 987, "url": "https://…/videos/download/<uploadId>.mp4",
        "tipo_foto": "despues", "mime_type": "video/mp4" }
    ],

    "mensajes": [
      { "id": 55, "mensaje": "texto", "enviado_por": "…" }
    ]
  }
]
```

- **`id` obligatorio en cada hijo** (imagen, vídeo-como-imagen, mensaje). Es la clave de dedup.
- Los **vídeos van dentro de `imagenes[]`** con `mime_type` `video/*` y la `url` `.mp4`. La app
  NO consume un array `videos[]` separado (modela el vídeo como imagen con mime de vídeo). Si
  preferís `videos[]` aparte, avisad: implica trabajo extra en cliente.
- `client_id` NO es necesario en la respuesta.

---

## 3. Sin arbitraje de conflictos (§8)

No devolver `409`. El cliente resuelve por propiedad del dato según `estado`
(`propuesta`/`validada` = backend; `contratista`/`ejecucion` = local). El backend solo sirve
`propuesta`+`validada` y no valida el valor de `estado` recibido en el upsert.

---

## 4. Checklist backend

**Identidad hijos por `id`:**
- [ ] Imagen (`POST /segmentos/{id}/imagenes`): lee field `id` → insert si 0/null, update si >0; responde con la entidad + `id`.
- [ ] Mensaje (`POST /segmentos/mensajes/{id}`): lee `id` del body → insert/update; responde con `id`.
- [ ] Vídeo init (`POST /videos/upload`): lee `id` del body → insert/update del registro.
- [ ] Vídeo complete: responde `{ uploadId, id, status }` con el `id` entero del registro.
- [ ] `client_id` NO usado como clave; no obligatorio devolverlo.

**Descarga contratista:**
- [ ] `GET /api/enagas/v1/segmentos/contratista` registrada; `cts` del querystring (CSV nombres, comas literales, opcional → todos).
- [ ] HMAC verificado sobre `"{tsMs}:GET:{path+querystring}"` sin re-encodear.
- [ ] Devuelve solo estados `propuesta` + `validada`.
- [ ] `imagenes[]` con `id`, `url`, `tipo_foto`, `mime_type`; vídeos como fila de `imagenes[]` con el mismo `id` del complete.
- [ ] `mensajes[]` con `id`, `mensaje`, `enviado_por`.
- [ ] Sin `409`.
