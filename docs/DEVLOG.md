# DEVLOG

## 2026-07-09 — Feature: borrar de local al subir + descarga solo-nuevos (mata la duplicidad de media)

**Modelo de dominio (responsable):** todo lo que se sube al backend pasa a un estado de revisión en la
web y **desaparece de la app del operario**. Por eso el "problema de duplicidad de media" era **ficticio**:
copia local y de nube nunca coexisten → no hay que deduplicar nada. La regla es: subir OK → borrar de local.

**A) Purga tras subir (`lib/data/sync/purge_synced_segmento_usecase.dart`, NUEVO).** Tras el drain en la
pantalla "enviar a nube", borra segmento + imágenes + vídeos + mensajes (fila + fichero local + job outbox)
en **transacción atómica**, y **solo si TODO está sincronizado** (ningún job pending/syncing/rejected en el
segmento ni en ningún dependiente). Si algo falló → no se borra nada de ese segmento (se conserva para
reintento). Invariante clave contra pérdida de datos: el set de no-sincronizados se lee **fresco por
segmento y después** de enumerar dependientes (un snapshot compartido en el batch podía juzgar "sincronizado"
un ítem capturado a media pasada y borrarlo con su fichero). Cableado en `forzar_envio_controller` tras
`enviarCloud`/`enviarAllCloud` (salvo `authExpired`).

**B) Descarga solo-nuevos (`sincronizacion_controller`).** Quitado el **abort** por cambios pendientes: la
descarga corre igual y avisa de forma **no bloqueante** (mismo mensaje). El pipeline de pull existente ya
protege lo sucio (conflicto → avisa, no pisa) y refresca lo limpio (estado + media de nube embebida). Se
descartó un intento de "add-only" en el fetcher que **congelaba los segmentos limpios** (habría bloqueado la
llegada de media de nube) — el fetcher NO filtra filas locales.

**Descartado por sobre-ingeniería (feedback del responsable):** un `SegmentoTombstoneStore` que el agente de
fix metió para evitar que un segmento borrado "reapareciera" en la descarga. Contradecía el modelo (subido →
sale del scope del operario, el backend no lo devuelve) y era permanente + sin límite. Eliminado. Ver memoria
`feedback_no_overengineering`.

**Verificación:** `flutter analyze` limpio; **457 tests pass** (purga: cascada completa + ficheros, y el caso
crítico "un dependiente sin subir → NO borra NADA"; descarga con aviso no bloqueante; wiring de purga).

## 2026-07-09 — Feature: media de nube (fotos + vídeos) en Antes/Después + reproducción de vídeo remoto

**Objetivo:** los segmentos descargados de nube deben mostrar en Antes/Después TODO el media de
nube (fotos **y** vídeos), fusionado con las capturas locales nuevas, y los vídeos de nube deben
reproducirse. Dato clave del backend: **no hay tabla de vídeos** — la tabla `imagenes` guarda todo
el media; un vídeo es una fila de `imagenes` cuyo `mime_type` es `video/*`. Los vídeos de nube ya
llegan embebidos en `segmento.imagenes[]`.

**Diseño (view-model normalizado, tras destruir el diseño en review adversarial):** en vez de un
tercer subtipo del sealed (que codificaba dos ejes: clase de media × origen/entidad), un único
`SegmentoMediaItem` (`lib/presentation/detalle/segmento_media_item.dart`) con `isVideo` +
`remoteUrl?`/`localPath?` nullables. El widget ramifica solo por `isVideo`; nunca inspecciona la
entidad backing. Escala a nuevos tipos de media con un campo, no un tipo.

**Cambios (solo cliente — backend ya manda los vídeos):**
- `segmento_media_item.dart` (NUEVO) — view-model con factories `.imagen`/`.remoteVideo`/`.localVideo`.
- `segmento_detalle_controller.dart` — `_esVideo(ImagenSegmentoEntity)` (mime `video/*` + fallback
  extensión probando **filename y url**, recortando querystring); `mediaPorTipo` fusiona 3 fuentes
  (fotos nube+local, vídeos nube, vídeos locales) + dedup vídeo nube↔local por `clientId` (gana
  local, reproduce offline) + orden `capturadaAt`. Borrado el sealed viejo.
- `segmento_detalle_page.dart` — carrusel ramifica por `item.isVideo`; `_CarouselSlide`/`_VideoSlide`
  toman `SegmentoMediaItem`; `_VideoSlide._open` reproduce fichero local, si no url remota, si no snack.
- `video_player_page.dart` — constructor `VideoPlayerPage.network(url)` → `VideoPlayerController.networkUrl`.

**Riesgos documentados (dependencias inherentes, no resolubles solo en cliente):**
1. **Dedup local↔nube depende de que backend ecoe `client_id`.** Tras subir + pull, la copia de nube
   llega en `imagenes[]`; se une a la local por `clientId`. Si backend no ecoa `client_id`, `fromJson`
   acuña UUID nuevo → el mismo vídeo aparece 2 veces. Agravado por el remux mov→mp4 (cambia filename →
   no sirve de fallback). Mismo riesgo latente que las fotos.
2. **Auth de reproducción de vídeo-nube.** Se asume que la `url` se sirve como las imágenes (sin HMAC).
   Si apunta al endpoint firmado `/videos/download/{id}.mp4`, el streaming rompe (HMAC exige firma
   fresca ±5 min por range-request; `video_player` no re-firma). `VideoPlayerPage.network` admite
   headers opcionales; verificar en runtime; si 401 → follow-up firmar/proxy.

**Verificación:** review adversarial 3 lentes (workflow ultracode) → 0 críticos/mayores, 3 minores
aplicados (`_esVideo` robusto + 2 tests). `flutter analyze` limpio; **436 tests pass** (11 en detalle:
clasificación mime, fallback filename+url, dedup local-wins, orden, `onDelete` fotos y vídeos).

## 2026-07-09 — Fix: fotos/vídeos antes/después se perdían al recrear la vista + botón Guardar fijo

**Bug:** tras añadir media a los tabs Antes/Después, al navegar al listado/mapa y volver
(o al recrear el controller por cualquier vía) las capturas desaparecían del carrusel,
aunque seguían en SQLite. Causa raíz: la media local se enlazaba al segmento por el **id
de nube** (`segmento_id` int, `= 0` mientras el segmento no está subido, que es el estado
normal de trabajo de campo). Además `_loadImagenes`/`_loadVideos` hacían early-return
cuando `segmento.id == null` y solo re-mostraban la lista remota embebida (vacía en campo).
Resultado: capturas huérfanas bajo `segmento_id = 0` (colisionando entre segmentos) e
invisibles tras cualquier recreación.

**Fix (FK por id local = `clientId`):**
- `imagen`/`video` entity: nuevo campo `segmentoClientId` (nullable) + enum + `toMap`/`fromMap`
  + param constructor. `toJson` **sin tocar** (contrato backend FK-by-clientId sigue pendiente).
- `imagen`/`video` local store: `schemaVersion 1→2`, migración escalonada (v1→v2 `ALTER TABLE
  ADD COLUMN segmento_client_id` + índice). Fresh installs corren v0→v1→v2; DBs de dev en v1
  reciben solo el ALTER.
- repos: `getAllBySegmento(int)` → `getAllByClientId(String)` (`findWhere('segmento_client_id', …)`).
- controller: capturas escriben `segmentoClientId: segmento.clientId`; lecturas por `clientId`
  (fuera el early-return `id==null`); tras guardar, recarga siempre.
- Nota: capturas hechas ANTES de esta migración (columna NULL) no reaparecen — app no está en
  producción, dato de dev desechable, sin backfill (YAGNI).

**UX botón Guardar:** movido a barra fija al fondo del tab Datos (fuera del scroll), full-width,
solo visible en ese tab (Guardar solo persiste estado/tipo/descripción; fotos/vídeos/mensajes ya
se guardan solos al capturar/enviar).

**Verificación:** `flutter analyze` limpio; 35 tests pass (stores imagen/video con test de query
por `clientId` + migración escalonada 0→1→2, repos, controller detalle).

## 2026-07-04 — Rediseño UI pantalla Sincronización (datos maestros)

**Motivo:** la pantalla usaba Material genérico (una Card, 6 ListTiles idénticas,
botón por fila + "Descargar todo") mientras el resto del módulo usa el lenguaje
visual de `app_theme.dart`. Desentonaba y no daba lectura de "¿estoy listo para
campo?".

**Cambios (solo presentación):** reescritura de `sincronizacion_page.dart` adoptando
`AppColors`/`AppTextStyles`/`AppSpacing` y el patrón de la hermana `forzar_envio`
(AppBar verde-claro + subrayado). Nueva **tarjeta-resumen "listo para campo"**: chip
de conectividad, barra segmentada (una pastilla por ítem coloreada por estado),
conteo simple `N de M al día`, acción primaria `Descargar todo`/`Actualizar todo` o
`Cancelar` mientras trabaja, y banner de error inline. Lista de ítems agrupada con
icono de estado, meta en una línea limpia (adiós al `\n`) y acción por icono
(↓ descargar / ↻ re-descargar).

**Alcance (con sign-off):** navegación **sin cambios** (única salida = flecha
atrás→login); controller y `sync_models.dart` **intactos** — `readiness` derivado en
el widget. Descartado: distinción esencial/opcional, botón "ir a segmentos", tokens
`AppColors.error/warning` (tocaría el tema compartido — follow-up).

**Reviews (ultracode, 2 agentes en paralelo):**
- Dart/Flutter: 2 bugs reales — `_readiness` contaba filas en `error`/`downloading`
  como "al día" si tenían `lastDownloadAt` (→ "Listo" verde con una fila fallando);
  `rows` vacío al arranque mostraba "Faltan 0 descargas". Ambos corregidos (estado
  `Cargando…`, `done` exige `success || (idle && lastDownloadAt)`).
- UX: contraste WCAG del headline ámbar/naranja (→ `#E65100`/`orange.shade900`),
  touch target del CTA (46→48dp), `Semantics` en barra segmentada y progreso de fila,
  microcopy de reintento en el banner, layout-shift del trailing (40→48).

**Ficheros:** `lib/presentation/sincronizacion/sincronizacion_page.dart` (reescrito).

**Verificación:** `dart analyze` limpio. Pendiente: correr app y validar visual en vivo.

## 2026-07-01 — Fix: master-data (gasoductos/pks/hitos) no descargaba (barra 0/N, sin datos)

**Síntoma:** en la página de sincronización, gasoductos "colgaba minutos", pks/hitos
terminaban sin cargar nada, barra clavada en "0/45". Datos de usuario OK (otro path).

**Causa raíz:** `app_di.dart` registraba `GasoductosService`/`PksService`/`HitosService`
en get_it (`registerLazySingleton`) **sin llamar `onInit()`**. get_it NO dispara el
lifecycle de `GetxService`, así que estos services nunca se suscribían a las TypedActions
`geoJsonLoaded`/`geoJsonLoadCompleted`. El `TaskPipeline` descargaba y dispatchaba los
eventos, pero sin listener: `processedFiles` no subía (barra 0/N) y `_entitiesBuffer`
quedaba vacío (descarga sin efecto). Footgun documentado en `feedback_di_getit_vs_getx_separate`.

**Descartado:** la petición era correcta. Verificado en vivo con la firma HMAC de la app:
`GET /api/enagas/v1/tracks/json/ct-almeria-{gasoductos|pk|hitos}.json` → 200. Firma, URL y
esquema idénticos al webapp (mismo `ctsbyuser` → `UserCt.ct` → `filename: u.ct`). El `CT10`
del fixture es un placeholder inexistente (404), no un bug de la app.

**Fix principal:** `..onInit()` en las tres factories de `app_di.dart` (mismo patrón que
Network/Connectivity/AuthExpirationHandler). Reordenadas las filas de sync
(`MasterDataKind`): segmentos, user, pks, hitos, gasoductos, posicionesFijas.

**Bugs secundarios (aplicados):**
- **Cancel cooperativo:** `_FileDownloadTask` recibe el `CancelToken` y corta si
  `isCancelled` → salta los ficheros restantes al instante (el en-vuelo termina por
  timeout Dio). Antes: cancelar no hacía nada → había que matar la app.
- **Sin éxito silencioso:** en los 3 services, si la descarga de red completa con
  `processedFiles==0 && totalFiles>0` (todo falló) → `throw` → fila **error** en vez de
  verde. Parcial (`0<ok<N`) → `AppLog.w`. Un fichero legítimamente vacío (200 sin
  features) dispara éxito → `processedFiles>0`, no cae en el throw.

**Ficheros:** `lib/core/app_di.dart`, `lib/presentation/sincronizacion/sync_models.dart`,
`lib/data/services/json_loader_service.dart`, `lib/core/services/{gasoductos,pks,hitos}_service.dart`.
Tests: `test/core/services/{gasoductos,pks}_service_test.dart` (fix test (d) → simula 1
fichero descargado-vacío), `test/presentation/sincronizacion/sincronizacion_controller{,_pull}_test.dart`
(registran `MockHitosService`, faltaba desde que se añadió `hitos` — rojo pre-existente).

**Verificación:** `flutter analyze` limpio; tests de services (8/8) y de sync verdes.
Pendiente: correr app y confirmar descarga real.

---

## 2026-07-01 — Nueva entidad master-data "hitos" (réplica de pks)

Añadida entidad `hitos` al proceso de sincronización, replicando EXACTAMENTE el pipeline de
`pks`. Mismo tipo de dato (puntos GeoJSON descargados del backend), misma mecánica: descarga
online multi-fichero vía `JsonLoaderService`, caché SQLite, capa de marcadores en mapa, fila
en la página de sincronización.

Fichero backend esperado: `{filename}-hitos.json` (ej. `ct-almodovar-hitos.json`), análogo a
`{filename}-pk.json`.

Nuevos:
- `lib/domain/entities/hito_entity.dart` — `HitoEntity` (misma forma que `PkEntity`).
- `lib/core/services/hitos_service.dart` — `HitosService` (`kFileGroupHitos='hitos'`, tabla `hitos`).
- `lib/presentation/mapa/layers/hitos_map_layer.dart` — `HitosMapLayer` (estilo idéntico a `PksMapLayer`, gate zoom>14).

Modificados:
- `api_endpoints.dart` — `hitosTrack(filename)`.
- `ct_info_entity.dart` — getter `hitosUrl`.
- `local_database.dart` — `_HitoSchemaShim` + `migrateEntity` (tabla `hitos`, PK `(id,ct_id)`).
- `app_di.dart` — registro `HitosService` + getter `AppDI.hitosService`.
- `sync_models.dart` — `MasterDataKind.hitos` (+ title/description).
- `sincronizacion_controller.dart` — `HitosService` en constructor/campo + case en `_runOne`.
- `mapa_global_controller.dart` — `isLoadingHitos`/`errorHitos`, `loadHitos()`, wiring en `loadAll`/`reloadAll`/`isLoading`.
- `mapa_global_page.dart` — `HitosMapLayer` en el stack del mapa.

Prueba de extensibilidad: cero cambios en el motor `lib/core/sync/`. Verificación: `flutter analyze` limpio.
Pendiente sign-off UX: `HitosMapLayer` sale visualmente idéntico a `PksMapLayer` (mismo amarillo) —
si conviene distinguir hitos de PKs, cambiar color/estilo.

## 2026-07-01 — Arranque lento splash→login (2 fixes en AppDI.init)

Splash tardaba varios segundos en pasar a login. Dos causas en el path de `AppDI.init()`:

1. **`ConnectivityService.onInit` bloqueaba el arranque.** Hacía `await checkConnectivity()`
   + `_hasActualInternet()` (DNS `InternetAddress.lookup`, timeout 5s) *dentro* de
   `DI.allReady()`. Si `checkConnectivity()` devolvía `none` un instante al arrancar (común
   en iOS), el splash se colgaba hasta 5s en el DNS.
   Fix: `onInit` registra el listener (síncrono) y resuelve el primer estado en background
   (`unawaited(_resolveInitialStatus())`); `_isConnected` arranca optimista (`true`).
   DNS timeout 5s→3s.
2. **`AuthDataProvider._network` eager → sesión nunca restaurada.** Campo
   `final _network = AppDI.networkService` se resolvía en construcción; `AppDI.init` construye
   `AuthRepositoryImpl` para `isAuthenticated()` ANTES de registrar `NetworkService` → `di.get`
   lanzaba "not registered" → el `catch` ponía `sessionState=false` en cada arranque (y el
   `read` real de keychain nunca corría). Fix: `_network` pasa a getter lazy.

- `lib/core/services/connectivity_service.dart` — onInit no bloqueante; DNS 3s.
- `lib/data/providers/auth_data_provider.dart` — `_network` getter lazy.

Verificación: `flutter analyze` limpio; hot restart en iPhone físico sin runtime errors.
Nota: retraso login→sincronización es latencia de red (login `POST`+`GET cts`), no AppDI.

## 2026-07-01 — Inyección de HMAC_SECRET (fix login 401 + builds de tienda)

Login daba `401 {"error":"Firma HMAC inválida"}`: la app corría con el placeholder
`YOUR_HMAC_SECRET_HERE` (sin `--dart-define=HMAC_SECRET`). El código HMAC era correcto;
faltaba inyectar el secret. Verificado con curl a `/api/enagas/v1/users/login`
(secret real → 200; placeholder → 401). Modelo copiado de `leulit_helireport_enagas_webapp`.

- `.env` — nuevo; **única fuente** del secret. `HMAC_SECRET=` (mismo valor que backend
  `.env enagas_HMAC_SECRET` y webapp).
- `.vscode/launch.json` — nuevo; `--dart-define-from-file=.env` (debug/profile/release). NO hardcodea el valor.
- `build-android.sh` / `build-ios.sh` — copiados de la webapp; `flutter build … --dart-define-from-file=.env`
  (guard grep que falla si `.env` no trae la clave → no se sube build roto).

El valor solo aparece en `.env` (verificado: 0 duplicados en launch.json/scripts). `.env` committeado
(app aún no en prod). CI/CD desde GitHub Secret sigue pendiente.

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

---

## 2026-07-01 — fix(pull): segmentos por CTS enviaba ctids en vez de nombres

**Síntoma:** la página de segmentos agrupados por CT no mostraba nada en la app,
aunque el mismo usuario en la web obtenía la lista correctamente vía
`GET /api/enagas/v1/segmentos/bycts/{cts}`.

**Causa raíz:** `SegmentoRemoteFetcher.pullAll` leía `user_cts` (que persiste
**ctids** enteros vía `jsonEncode(user.ctsId())`) y los enviaba al endpoint
`bycts/{cts}`, que **keyea por nombres de CT** (`ct-burgos,ct-plasencia,…`),
no por id. El backend no encontraba coincidencias → devolvía `[]` → el pull
importaba 0 → store local vacío → listado vacío.

`user_cts` (ids) es correcto para el path de lectura/agrupación local
(`GetSegmentosUseCase` → `findByCts(List<int>)`); solo el fetch remoto usaba la
clave equivocada.

**Fix:** el fetcher lee los **nombres** de CT desde el usuario persistido
(`user_json` → `UserCt.ct`) y los envía URL-encodeados y separados por coma.
No se toca `user_cts`. No requiere re-login (el `user_json` ya está guardado):
basta con volver a lanzar la descarga ("Descargar" / "Preparar trabajo de campo").

**Fichero:** `lib/data/sync/segmento_remote_fetcher.dart`.

---

## 2026-07-01 — fix(sync): barra de progreso de segmentos no avanzaba

**Síntoma:** al pulsar "Descargar" en la fila de **segmentos**, la barra no avanzaba
ni mostraba nada; tras unos segundos, al terminar, simplemente desaparecía.

**Causa raíz:** el pull de segmentos es una **única** `GET /segmentos/bycts` (sin
paginar) dentro de `PullCoordinator` (que ya usa `leulit_pipeline_pattern`, 6 tasks).
Nadie propagaba progreso a la fila → `row.progress` quedaba `null` →
`LinearProgressIndicator(value: null)` = indeterminado: se anima pero nunca rellena,
y al pasar `isDownloading=false` se quita. gasoductos/pks sí mostraban "3/12" porque
cuentan N ficheros vía RxInt.

**Fix (decisión con sign-off — opción "pasos + etiquetas"):** se surfacean los
eventos del `TaskPipeline` del pull hasta la UI.
- Nuevo `PullProgress { double? fraction; String phase; }` (`lib/core/sync/pull/pull_progress.dart`).
- `PullCoordinator.pullNow` acepta `onProgress`, se suscribe a `pipeline.events` y mapea
  `taskStart`/`taskSuccess` → fracción (`completed/total`) + etiqueta española por fase
  (`_phaseLabel`). El **primer** paso (el GET, duración desconocida) emite `fraction=null`
  → barra indeterminada animada durante la espera; los pasos rápidos de la cola la rellenan.
- `OfflineModule.runPull` reenvía `onProgress` (el facade genérico → cualquier entidad
  pulleable hereda progreso). `registerPullRunnerForTest` envuelve el runner estrecho →
  cero cambios en tests.
- El controller de sincronización actualiza `progress`/`progressLabel` de la fila; el
  subtítulo muestra la etiqueta directamente (`label ?? 'Descargando…'`). Se unificó el
  label de gasoductos/pks a "Descargando 3/12 archivos…".

**Alcance (con sign-off):** solo segmentos. gasoductos/pks conservan su progreso **real
por fichero** (mejor que pasos); usuario queda indeterminado (1 llamada, sin sub-pasos).
No se fuerza el patrón donde no aporta.

**Ficheros:** `pull_progress.dart` (nuevo), `pull_coordinator.dart`, `offline_module.dart`,
`sync.dart`, `sincronizacion_controller.dart`, `sincronizacion_page.dart`.

**Verificación:** `flutter analyze` limpio; `pull_coordinator_test` (15) + `sincronizacion` (9) verdes.

---

## 2026-07-09 — Fix: cámara no abría (crash en `Get.toNamed`)

**Síntoma:** pulsar "Cámara" en el diálogo de captura (`SegmentoDetalleController.capturarFoto`)
no abría la cámara. El overflow de 3.7px del `DropdownButtonFormField` (page:348) era ruido
cosmético no relacionado.

**Causa real:** `Get.toNamed<String?>(AppRoutes.camera)` →
`type 'GetPageRoute<dynamic>' is not a subtype of type 'Route<String?>?' in type cast`.
GetX construye SIEMPRE la ruta como `GetPageRoute<dynamic>`; Flutter (`_routeNamed<String?>`)
hace `route as Route<String?>?` y, por invarianza de genéricos, `Route<dynamic>` no es
`Route<String?>` → excepción **antes de navegar**. El error se veía solo en logcat
(`E/flutter`), no en runtime errors del DTD.

**Lección (gotcha reutilizable):** nunca parametrizar `Get.toNamed<T>` con un `T` no-dynamic
distinto del que GetX usa al construir la ruta. Navegar sin tipo (o `<dynamic>`) y castear el
`result`: `final r = await Get.toNamed<dynamic>(route); path = r as String?;`.

**Ficheros:** `segmento_detalle_controller.dart` (línea 313). `flutter analyze` limpio.

---

## 2026-07-09 — Feature: toggle Foto/Vídeo en la pantalla de cámara

**Síntoma:** tras el fix anterior, al elegir "Cámara" no había forma de elegir entre tomar
foto o grabar vídeo. La `CameraCapturePage` era solo-foto (un disparador, `takePicture()`);
el vídeo solo se grababa desde el tab Vídeos con la grabadora nativa (`pickVideo`).

**Decisión (con sign-off del usuario):** selector **Foto | Vídeo** dentro de la propia
pantalla de cámara (feel nativo), no un sub-diálogo.

**Cambios:**
- `camera_capture_page.dart`: modo `_CaptureMode {photo, video}`, `_ModeSelector` FOTO|VÍDEO,
  disparador que en vídeo hace `startVideoRecording`/`stopVideoRecording` (badge REC, corte
  auto a 3 min como la grabadora nativa). El micrófono solo se activa al entrar en modo vídeo
  (re-crea el `CameraController` con `enableAudio:true`; evita el prompt de audio al que solo
  hace fotos). Devuelve `({String path, bool isVideo})` (antes `String?`).
- `segmento_detalle_controller.dart`: `capturarFoto` interpreta el nuevo record y guarda como
  imagen o vídeo según el modo; `capturarVideo` (grabadora nativa) y la rama de vídeo de cámara
  comparten `_saveVideoFromPath` (DRY). `_tipoVideoDesde` mapea `TipoFoto`→`TipoVideo`. Un vídeo
  grabado desde el tab Fotos aparece en el tab Vídeos (antes/después preservado).

**Permisos:** ya declarados — Android `CAMERA`+`RECORD_AUDIO`, iOS `NSCameraUsageDescription`+
`NSMicrophoneUsageDescription`. Sin cambios nativos.

**Ficheros:** `camera_capture_page.dart` (reescrito), `segmento_detalle_controller.dart`.
`flutter analyze` limpio (2 items, 0 issues). Pendiente: prueba en dispositivo real
(cámara no verificable en analyzer).

## 2026-07-09 — Vídeo mudo + fusión foto/vídeo en tabs Antes/Después + guardar en galería

**Feedback del usuario (3 puntos, con sign-off):** (1) el vídeo debe grabarse SIN audio;
(2) al grabar vídeo desde el tab foto "Antes" no aparecía nada allí (iba al tab "Vídeo antes");
(3) las capturas no aparecían en la galería del dispositivo.

**Decisiones (validadas con el usuario):**
- Eliminar los tabs "Vídeo antes/desp.". Solo quedan "Antes" y "Después", que ahora muestran
  **fotos Y vídeos mezclados** en el mismo carrusel (ordenados por `capturadaAt`).
- Vídeo del carrusel: slide con póster negro + play → reproductor a pantalla completa in-app.
- Guardar toda captura de cámara (foto y vídeo) también en la galería del dispositivo.

**Cambios:**
- `camera_capture_page.dart`: `enableAudio: false` SIEMPRE (antes se recreaba el controlador con
  `enableAudio:true` al entrar en vídeo). `_setMode` ya no recrea el controlador → **vídeo mudo**.
  Nota: `image_picker.pickVideo` (grabadora nativa) graba con audio y no permite desactivarlo →
  por eso todo el vídeo pasa por el paquete `camera`.
- `segmento_detalle_controller.dart`: `capturarFoto`→`capturarMedia`; `imagenesPorTipo`+
  `videosPorTipo`→`mediaPorTipo` (lista fusionada `SegmentoMediaItem {ImagenMediaItem|VideoMediaItem}`,
  sealed, ordenada por captura). Nuevo `_saveToGallery` (paquete `gal`, best-effort, `GalException`
  se loguea sin abortar). Cámara→galería; galería-pick→no (ya está). Eliminado `capturarVideo`
  (grabadora nativa con audio, ya no se usa).
- `segmento_detalle_page.dart`: 6→4 tabs; `_ImagenesCarousel`→`_MediaCarousel` (switch sobre el
  sealed: imagen→`_CarouselSlide`, vídeo→`_VideoSlide`). Eliminados `_VideosTab`/`_VideoTile`.
- `video_player_page.dart` (nuevo): reproductor `video_player` a pantalla completa para fichero
  local; los vídeos ya subidos (sin fichero local) muestran aviso (playback remoto pendiente de
  `download_url` del backend).

**Deps:** `video_player: ^2.11.1`, `gal: ^2.3.2`.

**Nativos:** Android `WRITE_EXTERNAL_STORAGE` maxSdk 28→29 (gal). iOS: −`NSMicrophoneUsageDescription`
(ya no se graba audio) +`NSPhotoLibraryAddUsageDescription` (gal). `RECORD_AUDIO` Android se deja
(lo aporta el plugin `camera` vía merge; con `enableAudio:false` no se solicita al usuario).

**`flutter analyze lib` → 0 issues.** Pendiente: prueba en dispositivo real (cámara/galería no
verificables en analyzer).
