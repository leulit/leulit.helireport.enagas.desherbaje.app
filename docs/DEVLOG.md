# DEVLOG

## 2026-06-18 — Matriz de transiciones de estado de segmento (app campo)

Portado el patrón de la webapp: SSOT de transiciones en el enum `EstadoActividad`
+ defensa en profundidad (dropdown filtrado + guard antes de guardar).

**Decisiones del responsable (no las decidió Claude):**
- Matriz **adaptada a operario** (no la verbatim de la webapp): `contratista→ejecución`,
  `ejecución→finalizada`, `finalizada→{cerrada, ejecución}`. `propuesta`/`validada`/`cerrada`
  sin transición de salida ⇒ solo lectura desde la app de campo (los gestiona el gestor;
  `cerrada` es terminal). Permanecer en el mismo estado siempre es válido.
- Serialización: se **mantiene** `EstadoActividad.contratista.descripcion = 'contratista'`
  (no se alinea a `'contratita'` de la webapp). ⚠️ Pendiente confirmar con backend si comparten
  BD: `fromString` normaliza tildes pero no la `s` que falta, así que un `contratita` del
  backend caería a `propuesta`.

**Cambios:**
- `lib/domain/entities/segmento_entity.dart` — `transicionesPermitidas`, `esEditableDesdeApp`,
  `puedeIrA` en `EstadoActividad` (SSOT). Cambiar la matriz = tocar solo este getter.
- `lib/presentation/detalle/segmento_detalle_page.dart` — `_estadosEditables(origen)` filtra
  por `origen.puedeIrA` sobre el **estado original** (`controller.segmento.estado`), no el editable.
  Eliminada la lista fija `_estadosEditablesBase`.
- `lib/presentation/detalle/segmento_detalle_controller.dart` — `_validateEstado()` reemplaza a
  `_validateEstadoEditable()`; diálogos `_dialogEstadoBloqueado` / `_dialogTransicionInvalida`.
- Tests: grupo de matriz en `test/domain/entities/segmento_entity_test.dart`.

**Supuesto a validar:** `propuesta`/`validada`/`cerrada` se tratan como solo lectura **total**
(igual que el comportamiento previo): `guardar()` aborta con diálogo. Si se prefiere el patrón
webapp puro (editar descripción/fotos en esos estados y bloquear solo el cambio de estado),
relajar el primer branch de `_validateEstado()`.

Verificación: `flutter analyze` limpio; `flutter test` afectados 47/47 OK.

---

## 2026-06-19 — Formación: diapositiva 4 "ciclo de vida" redibujada (flujo real de estados)

`docs/formacion/build_flujo_deck.js` (S4) + regenerado `presentacion_flujo_informacion.pptx`.
La diapositiva era una línea recta `Propuesta→Contratista→Validada→Ejecución→Finalizada→Cerrada`,
que no reflejaba ni la rama ni el bucle. Ahora muestra dos caminos que confluyen + el bucle:

- **Casos 1-2 (ruta normal):** `Propuesta ─────► En Ejecución` (Enagas asigna la zona ya lista).
- **Caso 3 (operario propone):** `Propuesta → Contratista → Validada → En Ejecución`.
- **Bucle común:** `En Ejecución ⇄ Finalizada` (repetible n veces) → `Cerrada`.

**Nota de coherencia:** la diapositiva es el flujo **end-to-end (web Enagas + app móvil)**; la matriz
`EstadoActividad.transicionesPermitidas` es solo el **subconjunto del operario** (por eso
`propuesta`/`validada` no transicionan desde la app — los arranca el gestor en la web). No hay
contradicción: distinto alcance. Si en el futuro el operario pudiera arrancar ejecución sin pasar
por `contratista`, habría que ampliar esa matriz.

---

## 2026-06-26 — Feature: captura y subida de vídeos (entidad `VideoSegmentoEntity`)

Implementada feature completa de captura y subida de vídeos por segmento. Espejo mecánico de la entidad `imagen`.

**Decisiones clave (aprobadas por responsable):**
- Captura via `image_picker.pickVideo(source: camera, maxDuration: 3 min)` — sin nueva dependencia.
- Sin transcodificación cliente: Android graba `.mp4`, iOS graba `.mov` (H.264/AAC en ambos); backend remuxea `.mov→.mp4` con `ffmpeg -c copy` (sin recodificación, instantáneo).
- Transporte: subida chunked resumable (5 MB/chunk, timeout 120 s/chunk) via nueva facade `NetworkService.uploadFileResumable()`. `uploadOffset` persiste en SQLite por entidad; el adapter reanuda desde ese valor si el drain se interrumpe por pérdida de red.
- Motor outbox (`lib/core/sync/`) no tocado: nueva entidad registrada con `OfflineModule.registerEntity<VideoSegmentoEntity>()` en `app_di.dart`.

**Ficheros nuevos:**
- `lib/domain/entities/video_segmento_entity.dart` — `TipoVideo` enum, `VideoSegmentoEntity` (Syncable). `uploadOffset` en `toMap()` pero NO en `toJson()`.
- `lib/data/sync/video_local_store.dart` — `VideoLocalStore`, tabla `videos_segmento`, `saveUploadOffset()`.
- `lib/data/sync/video_remote_adapter.dart` — `VideoRemoteAdapter`, chunked upload via `_network.uploadFileResumable()`, `onChunkConfirmed` → `saveUploadOffset`.
- `lib/data/repository/video_repository_impl.dart` — `VideoRepositoryImpl`, espejo de `ImagenRepositoryImpl`.
- `docs/BACKEND_VIDEO_CONTRACT.md` — protocolo completo para equipo backend: endpoints, headers, idempotencia, remux, errores.
- `test/domain/entities/video_segmento_entity_test.dart` (18 tests)
- `test/data/sync/video_local_store_test.dart` (17 tests)
- `test/data/sync/video_remote_adapter_test.dart` (20 tests)
- `test/data/repository/video_repository_impl_test.dart` (2 tests)

**Ficheros editados:**
- `lib/data/network/network_service.dart` — añadido `uploadFileResumable()`.
- `lib/core/api_endpoints.dart` — añadidos `videoChunk` y `videoStatus()`.
- `lib/core/app_di.dart` — registro `VideoLocalStore` + `OfflineModule.registerEntity<VideoSegmentoEntity>`.
- `lib/presentation/detalle/segmento_detalle_controller.dart` — `capturarVideo()`, `_loadVideos()`, `videosPorTipo()`.
- `lib/presentation/detalle/segmento_detalle_page.dart` — tabs "Vídeo antes"/"Vídeo desp.", `_VideosTab`, `_VideoTile`.
- `lib/presentation/sincronizacion/sincronizacion_controller.dart` — suma vídeos al contador pendientes.
- `lib/presentation/forzar_envio/forzar_envio_controller.dart` — incluye `'video'` en drains.
- `android/app/src/main/AndroidManifest.xml` — permiso `RECORD_AUDIO`.
- `ios/Runner/Info.plist` — `NSMicrophoneUsageDescription`.

Verificación: `flutter analyze` limpio; 55/55 tests nuevos OK.

---

## 2026-06-26 (tarde) — Reescritura a protocolo real de subida de vídeo + doble esquema HMAC

Backend entregó la spec real del protocolo. La implementación anterior usaba endpoints y
esquema HMAC asumidos. Esta PR (`fixes/outbox-review`) reemplaza todo.

**Cambios de protocolo:**
- Endpoints anteriores (`POST /operador/video/chunk`, `GET /operador/video/{id}/status`) **eliminados**.
- Nuevos endpoints TUS-like en `/api/enagas/v1/videos/...`: Init → Chunk (PATCH) → Status (GET) → Complete (POST).
- Nuevo identificador de sesión: `upload_id` (UUID asignado por servidor). El `client_id` del cliente viaja en el body del Init para idempotencia.
- Nuevo campo `uploadId` en `VideoSegmentoEntity` (columna `upload_id` en SQLite). `remoteId` getter retorna `uploadId ?? id?.toString()`.

**Doble esquema HMAC — decisión de aislamiento:**
- Rutas legacy (segmento/imagen/mensaje/positions): `x-flutter-signature` + `x-flutter-timestamp` (segundos) + `x-flutter-nonce` + `Authorization: Bearer`. Sin cambio.
- **Rutas de vídeo (nuevo):** `X-HMAC-Signature` + `X-Timestamp` (milisegundos). Sin nonce. Sin Bearer.
- Payload nuevo: `"{ms}:{METHOD_UPPERCASE}:{path}"`. Ventana anti-replay ±5 min.
- `ApiSecurityService.buildEnagasVideoHeaders(method, path)` — nuevo método estático. `buildHeaders` legacy intacto.
- `NetworkService._videoDio` — instancia Dio separada (4 min timeout, sin interceptors HMAC ni retry). 4 métodos específicos: `initVideoUpload`, `patchVideoChunk`, `getVideoStatus`, `completeVideoUpload`. `uploadFileResumable` eliminado.

**Regla crítica: 401/403 en vídeo ≠ logout.**
`VideoRemoteAdapter._mapNetworkError` maneja `unauthorized` → `SyncUnrecoverable("HMAC signature rejected")`. NO usa `syncOutcomeFromNetworkError` (que lanzaría `AuthExpiredException` y desloguearía al operario). Los demás adapters siguen usando el helper estándar.

**Ficheros modificados:**
- `lib/core/services/api_security_service.dart` — añadido `buildEnagasVideoHeaders`.
- `lib/core/api_endpoints.dart` — endpoints de vídeo reemplazados (4 nuevos, 2 eliminados).
- `lib/data/network/network_service.dart` — `_videoDio` + 4 métodos de vídeo, eliminado `uploadFileResumable`.
- `lib/domain/entities/video_segmento_entity.dart` — campo `uploadId`, `remoteId` getter, `toMap/fromMap/copyWith`.
- `lib/data/sync/video_local_store.dart` — columna `upload_id`, `saveUploadId()`, `markSynced` distingue int vs UUID.
- `lib/data/sync/video_remote_adapter.dart` — reescritura completa: state machine Init→Chunk→Complete, retry por chunk, `_mapNetworkError` personalizado.

**Tests reescritos:**
- `test/core/services/api_security_service_test.dart` — nuevo: cubre `buildEnagasVideoHeaders` (ts ms, HMAC correcto, sin Bearer) + sanity check legacy.
- `test/data/sync/video_remote_adapter_test.dart` — reescritura completa con `_FakeNetworkService` queue-based.
- `test/data/sync/video_local_store_test.dart` — añadidos: `upload_id` column, `saveUploadId`, `markSynced` UUID.
- `test/domain/entities/video_segmento_entity_test.dart` — añadidos: `uploadId` round-trip, `remoteId` fallback, `copyWith`.

Verificación: `flutter analyze` limpio; `flutter test` 401/401 OK.

---

## 2026-06-30 — Unificación del esquema HMAC + migración de endpoints a `/api/enagas/v1`

**Causa raíz del 401 en login y descarga de segmentos:** los endpoints REST habían migrado al prefijo
`/api/enagas/v1` (alineándose con los de vídeo) pero el firmador HMAC del `_HmacInterceptor` del Dio
principal seguía usando el esquema legacy (`x-flutter-*` + nonce + timestamp en segundos). El backend solo
valida el esquema nuevo (`X-HMAC-Signature` / `X-Timestamp` en ms, payload `{ts}:{METHOD}:{path}`);
el síntoma era engañoso: el login devolvía 401 y `_parseError` lo mapeaba a "Usuario o contraseña
incorrectos".

**Cambios aplicados:**

- **Prefijo API unificado:** `AppConfig.apiBaseUrl = baseUrl/api/enagas/v1`. Todos los endpoints
  REST (login, segmentos, mensajes, imágenes, positions, tracks JSON) apuntan ahora a ese prefijo.
  Los endpoints de vídeo pasan de `/api/enagas/v1/videos/...` a `apiBaseUrl/videos/...` sin cambio
  efectivo de URL.
- **Firmador unificado:** borrado `buildHeaders` (esquema legacy `x-flutter-*` + nonce, segundos).
  `buildEnagasVideoHeaders` renombrado a `buildHmacHeaders`. `_HmacInterceptor` reescrito para
  llamar a `buildHmacHeaders`, extrayendo el path relativo de `options.uri` con prefijo `/api/enagas/v1`.
- **Secret por `--dart-define`:** `AppConfig.hmacSecret = String.fromEnvironment('HMAC_SECRET')`.
  El placeholder por defecto no valida contra el backend real.
- **Sin cambio en la regla 401/403 de vídeo:** `VideoRemoteAdapter._mapNetworkError` sigue capturando
  `unauthorized` → `SyncUnrecoverable` (sin logout). La unificación del esquema no afecta esa regla.

**Ficheros modificados:**
- `lib/core/services/api_security_service.dart` — borrado `buildHeaders`, renombrado a `buildHmacHeaders`.
- `lib/data/network/network_service.dart` — `_HmacInterceptor` reescrito; `AppConfig.apiBaseUrl` aplicado.
- `lib/core/app_config.dart` (o equivalente) — `hmacSecret` vía `String.fromEnvironment`.
- `lib/core/api_endpoints.dart` — prefijos de endpoints actualizados a `apiBaseUrl`.
- Tests de `api_security_service`, adapters y sincronización actualizados.

Verificación: `flutter analyze` limpio; 396/396 tests verdes.

**Pendiente:** inyectar el secret real (64-hex, desde GitHub Secret devops) y verificar login en
dispositivo físico contra `https://enagastool.helireport.com`.
