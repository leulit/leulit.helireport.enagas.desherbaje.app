# DEVLOG

## 2026-07-20 — Hitos/PKs en el mapa: clustering con supercluster

**Síntoma:** los hitos no aparecían en `mapa_global_page`. Los PKs sí (a duras penas).

**Diagnóstico (estado leído en vivo del dispositivo por VM Service, no por inspección de
código):** la descarga y el parseo funcionaban — caché SQLite con 48.073 hitos y 12.965 PKs,
y el backend sirve bien los `{ct}-hitos.json` (verificado contra prod: `ct-almeria` 1019
features `Point`, `ct-toledo` 1331, propiedad `name`). El fallo estaba en el render:
`HitosMapLayer` construía un `Marker` (`Container` + `CustomPaint`) por CADA punto cargado,
sin culling. A zoom > 14 eso son 48k widgets en un `MarkerLayer` → el frame no se completa y
la capa se ve vacía. Los PKs, con 4× menos puntos, aún salían: de ahí la asimetría engañosa.

**Solución** — se adapta la lógica de render de la webapp (`MarkerManagerOptimized`), pero SIN
portar el fichero: la webapp arrastra facade web/mobile, `export_core` entero y features que
aquí no se usan (drag de markers, filtros por tipo/CT). El núcleo útil son ~60 líneas:

- `clustered_marker_layer.dart` — `ClusteredMarkerLayer<T>` genérico. Indexa los puntos UNA vez
  en `SuperclusterImmutable` (`radius: 80`, `extent: 512`, `minPoints: 2`, `maxZoom: 20`) y en
  cada cambio de cámara (`MapCamera.of(context)`, que ya reconstruye la capa al panear/zoom)
  hace `index.search(west, south, east, north, zoom)` → devuelve solo clusters + puntos del
  viewport. El índice se reconstruye solo si cambia la lista, no en cada pan. Tap en cluster →
  `MapController.of(context).move(pos, highestZoom + 3)`.
- `point_label_marker.dart` — `_PkMarker` y `_HitoMarker` eran el mismo widget duplicado; ahora
  uno solo con `fill` parametrizado (`0xFFFFC107` PK, `0xFF81D4FA` hito).
- `PksService.pks` / `HitosService.hitos` pasan de `RxList` a `ValueNotifier<List<T>>`; las capas
  usan `ValueListenableBuilder` y ya no importan `get`. Nadie más consumía esas listas.
  `isLoading`/`totalFiles`/`processedFiles` siguen `.obs` porque `sincronizacion_controller` los
  lee con workers de GetX.
- `mapa_global_page` monta `const PksMapLayer()` / `const HitosMapLayer()`: el parámetro
  `currentZoom` sobraba, el gate de zoom vive ahora en la capa (`minZoom = 14`).

**Bug colateral corregido:** los marcadores usaban `alignment: Alignment.bottomCenter`, que en
flutter_map coloca el widget DEBAJO del punto ("`Alignment.topCenter` will mean the entire marker
widget is located above the point"), así que el pico del triángulo caía ~30 px al sur de la
coordenada real y lo que tocaba el punto era el borde superior de la etiqueta. Ahora `topCenter`.

**Verificado en dispositivo:** 61.038 puntos indexados, 12 markers en el árbol de widgets a
zoom 19,25; sin runtime errors.

**Lección:** una capa clonada hereda el techo de rendimiento del original. `PksMapLayer` funcionaba
por accidente de volumen; copiarla para hitos (4× más puntos) la llevó por encima del límite. Ante
"los datos no se ven", medir el estado en runtime antes de sospechar de la descarga: aquí el dato
llevaba desde el principio en SQLite.

## 2026-07-20 — Eliminar segmento local (sin id remoto)

Botón "Eliminar" en la barra de acciones de `segmento_detalle_page`, visible solo cuando
`segmento.id` es `null` o `0` (segmento creado en campo que nunca llegó al backend).
Diálogo Sí/No; "Sí" dispara `AppTypedActions.deleteSegmento` (nueva TypedAction sin payload).

`SegmentoDetalleController.eliminarSegmento()` escucha la acción y purga en local: fotos,
vídeos (más sus ficheros en disco), mensajes y la fila del segmento, cada uno vía
`purgeLocal` del `OfflineRepository` correspondiente (borra fila + jobs de outbox en una
transacción, sin encolar borrado remoto). Guarda de seguridad redundante en el controller:
si `id != null && id != 0` aborta con snack. Añadidos `purgeLocal` passthrough en
`SegmentoRepositoryImpl` y `MensajeSegmentoRepository`.

`segmentos_list_controller.goToDetalle` recarga al volver (`Get.toNamed(...)?.then((_) =>
loadSegmentos())`): tras eliminar (o editar) en el detalle, la lista en memoria quedaba
obsoleta y seguía mostrando el segmento borrado. Lectura local, coste despreciable.

## 2026-07-16 — Fix: alinear cliente sync con contrato backend (4 bugs HIGH)

Validación de la capa de sync contra la guía de cliente del backend (`/api/enagas/v1`).
Cuatro divergencias que rompían la subida; corregidas:

1. **Segmento upsert — campo `id`.** `segmento_remote_adapter.dart` mandaba `segmento_id`,
   que no está en el schema del backend → se descartaba en silencio → todo upsert se trataba
   como insert → idempotente por `client_id` → **los cambios de estado nunca se aplicaban**.
   Fix: body key `'segmento_id': entity.id` → `'id': entity.id ?? 0` (0/null=insert, >0=update).
2. **Fotos — endpoint equivocado.** `imagen_remote_adapter.dart` usaba el legacy
   `/operador/additem`, que ignora `segmentoId`/`tipoFoto`/`clientId` → foto nunca ligada al
   segmento (se perdía). Fix: `POST /segmentos/{id}/imagenes` (nuevo `ApiEndpoints.segmentoImagenes`),
   fields reducidos a los declarados: `clientId`, `tipoFoto` (antes|despues), `capturada_at`,
   `subida_por`. `imagenAdd`/`additem` se conserva SOLO para incidencias de operador.
3. **Vídeo — chunks con PATCH.** El backend solo registra POST para el chunk → PATCH daba 404 →
   subida de vídeo rota. La resumabilidad no depende del verbo (vive en `uploadId` + header
   `Upload-Offset` + body octet-stream). Fix: `network_service.patchVideoChunk` → `postVideoChunk`
   (verbo HMAC y llamada Dio a POST; header/offset intactos) + call site en `video_remote_adapter`.
4. **Vídeo — init snake_case.** `_doInit` mandaba `original_filename`/`total_bytes`/`mime_type`/
   `client_id`/`segmento_id`; el backend exige camelCase y `segmento_id` snake NO se lee → vídeo
   huérfano. Fix: `originalFilename`/`totalBytes`/`mimeType`/`clientId`/`segmentoId`.

**Conforme (sin tocar):** orden segmento→propaga id→hijos→sync-complete; idempotencia `client_id`;
mensajes (`/segmentos/mensajes/{id}`); sync-complete antes de purgar y no-purga-si-falla;
`segmento_client_id` es columna **local-only** (se manda `segmento_id` int tras propagar, no viaja
al backend — §10 del contrato); HMAC ms + path completo con prefijo+query.

**Pull migrado al endpoint contratista (antes MEDIUM).** `segmento_remote_fetcher` pasa de
`/segmentos/bycts/{cts}` (path) a `GET /segmentos/contratista?cts=CT1,CT2` (querystring), decisión
del responsable. Nuevo `ApiEndpoints.segmentosContratista(cts)`. La firma HMAC del interceptor ya
incluye el querystring (firma `options.uri`, path+query → auto-consistente). El endpoint devuelve
`propuesta`+`validada` enriquecidos con `imagenes[]`/`mensajes[]` (vídeos como fila de `imagenes[]`
con `mime_type` `video/*`, que es como la entidad los parsea) y `client_id` en cada hijo para dedup.
Instrucciones para backend: `docs/BACKEND_SEGMENTOS_CONTRATISTA.md` (endpoint pendiente de implementar
en el backend; la app ya apunta ahí). `segmentosByCt` queda definido como legacy sin callers.

**Identidad de entidades hijas por `id` remoto (no `client_id`) — decisión del responsable.**
Imagen/vídeo/mensaje siguen el MISMO patrón que SegmentoEntity: el payload lleva `id` (`0`/null=insert,
`>0`=update), el backend upserta por `id` y devuelve la entidad completa, el frontend lee el `id` y lo
persiste (`markSynced`). La dedup local↔nube en re-descarga se hace por `id` remoto (cuando un hijo puede
re-descargarse ya tiene `id` en ambos lados). `client_id` deja de ser clave de identidad/dedup. Razón:
reenvío tras fallo parcial hace UPDATE por `id` (no duplica) y el segmento no es visible hasta
`sync-complete` → sin colisión. Cambios: `mensaje_remote_adapter`/`imagen_remote_adapter` añaden `id` al
payload; `video_remote_adapter` manda `id` en init y lee el `id` entero del registro desde la respuesta de
`complete` (`{uploadId, id, status}`) → `entity.id` (degradación limpia a `uploadId` si el backend aún no
lo devuelve); `segmento_detalle_controller` migra las 3 dedups (`_loadImagenes`, `_loadMensajes`,
`mediaPorTipo`) de `clientId` a `id` (con guarda de `id == null` para hijos locales no subidos).
Backend debe: upsert de hijos por `id`, devolver `id` en cada uno (incl. `id` entero del vídeo en el
`complete`, mismo `id` que la fila de `imagenes[]` en descarga). Verificación: analyze limpio, 158/158
`test/data/sync/` + detalle tests.

Verificación: `flutter analyze` limpio en los 5 ficheros; 47/47 tests
(`video_remote_adapter_test`, `imagen_remote_adapter_mime_test`).

## 2026-07-10 — Feature: GIS en captura de foto/vídeo (`gis_json` GeoJSON por media)

**Objetivo:** al capturar foto o grabar vídeo desde la cámara propia de la app, registrar
**automáticamente** (sin aprobación del usuario) la posición y el rumbo del dispositivo y persistirlo
como GeoJSON en una columna nueva `gis_json` por media, para enviarlo al backend. Foto → un punto
(lat, lon, alt) + rumbo en el instante del disparo. Vídeo → el track completo a **1 muestra/seg**
durante toda la grabación. Si falta permiso de ubicación o no hay fix, la captura **no se bloquea**:
la media se guarda con `gis_json = null`. Media de galería → sin GIS. Diseño:
`docs/superpowers/specs/2026-07-10-media-gis-capture-design.md`.

**Esquema `gis_json` (top-level siempre `FeatureCollection`, orden GeoJSON `[lon, lat]`):**
- **Foto:** `Point` `[lon, lat, alt]`; `heading`/`heading_accuracy`/`gps_heading`/`accuracy_m`/
  `altitude_m`/`speed_mps`/`captured_at` en `properties` (`kind: "photo"`).
- **Vídeo:** `LineString` con **coordenada custom** `[lon, lat, alt, heading_deg, t_epoch_ms]` por
  vértice (evita arrays paralelos gigantes); `properties` lleva `coord_format`, `sample_interval_s: 1`,
  `started_at`/`ended_at` (`kind: "video"`). Degradación: 0 muestras → `gis_json` null; 1 muestra →
  geometría `Point` (kind sigue `"video"`); ≥2 → `LineString`.
- Ambos incluyen en `properties`: `kind`, `user_id`, `os`, `os_version`, `device_model`, `app_version`.

**Componentes nuevos (`lib/core/gis/`):**
- `media_gis_recorder.dart` — `MediaGisSample` (value type: lat/lon/alt/headingDeg/headingAccuracy/
  gpsHeading/accuracyM/speedMps/tsUtc) + `MediaGisRecorder` (Dart plano, ciclo de vida = página de
  cámara). `start()` pide permiso `whileInUse` y abre streams propios de `geolocator` (1 s) +
  `flutter_rotation_sensor` (azimuth); `snapshotPhoto()` → muestra única; `startTrack()`/`stopTrack()`
  → `Timer.periodic(1s)` que acumula muestras. **Independiente** del `GpsBackgroundService`
  (work-track de jornada): streams separados, coexisten. Permiso denegado → modo "sin GIS", nunca lanza.
- `media_gis_geojson.dart` — funciones **puras** (sin IO): `buildPhotoGeoJson(sample, {userId, meta})`
  y `buildVideoGeoJson(samples, {userId, meta})`; devuelven `null` sin muestra útil.
- `capture_meta.dart` — `CaptureMeta` (`os`/`os_version`/`device_model` vía `device_info_plus` +
  `app_version` vía `package_info_plus`) con `Future<CaptureMeta> captureMeta()` **memoizado**.

**Cambios de captura y detalle:**
- `camera_capture_page.dart` — instancia y `start()` del recorder en `_initCamera`; foto →
  `snapshotPhoto()`, vídeo → `startTrack()`/`stopTrack()`; `dispose()` limpia. Retorno de `Get.back`
  ampliado a `({String path, bool isVideo, Object? gis})` (`gis` = `MediaGisSample?` en foto,
  `List<MediaGisSample>` en vídeo).
- `segmento_detalle_controller.dart` — construye `gis_json` con el builder (`user.value?.id` +
  `captureMeta()`) y lo setea en `entity.gisJson` antes de `saveLocal`. Rama galería → null.

**Entidades y almacén:**
- `ImagenSegmentoEntity` y `VideoSegmentoEntity`: **eliminados** `latitud`, `longitud`, `fixedLatitud`,
  `fixedLongitud` (ninguno se poblaba) + **añadido** `String? gisJson` (enum `gis_json`), en
  `toMap`/`fromMap`/`toJson`/`fromJson`/`copyWith`. `toJson` envía `gis_json` al backend.
- `ImagenLocalStore` / `VideoLocalStore`: `schemaVersion 2 → 3`. Bloque nuevo `from < 3` con
  **table-rebuild** (`CREATE <t>_new` sin lat/lon + `gis_json TEXT` → `INSERT … SELECT` cols comunes →
  `DROP` → `RENAME` → recrear índices `seg`/`remote`/`segclient`), porque SQLite antiguo de Android no
  garantiza `DROP COLUMN`. App no está en producción → sin backfill, DBs de dev migran limpio.

**Deps nuevas (`pubspec.yaml`):** `flutter_rotation_sensor: ^0.3.0` (rumbo por azimuth, funciona
parado; sustituye a `flutter_compass` roto en AGP 8 sin `namespace`), `device_info_plus: ^13.2.0`,
`package_info_plus: ^10.2.0`. Sin permisos nuevos ni cambios de manifest/Info.plist (`whileInUse` basta).

**Contrato backend:** `gis_json` (GeoJSON) se añade al payload de foto y vídeo; `latitud/longitud/
fixed_*` se eliminan de ambos. Documentado en `docs/BACKEND_SYNC_CONTRACT.md`.

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

## 2026-07-10 — Georreferencia de la media activa en el mapa (Antes/Después)

Nuevo layer de `flutter_map` que dibuja la posición/rumbo (foto) o traza (vídeo) de la captura
visible en el carrusel Antes/Después, sobre el mapa de `_MapaSegmento`.

- `core/gis/media_gis_map_geometry.dart` (nuevo): parseo puro del `gis_json` (GeoJSON) —
  `parsePhotoGis` (Point + `properties.heading`/`gps_heading`), `parseVideoGis` (LineString o
  Point → lista de `LatLng`) — y geometría de flecha (`destinationPoint` great-circle,
  `arrowGeometry` asta+cabeza en V). Sin IO ni widgets; 11 tests en
  `test/core/gis/media_gis_map_geometry_test.dart`.
- `core/app_typed_actions.dart`: nuevo `TypedAction<MediaGisActivada>` `mediaGisActivada` +
  payload `MediaGisActivada {gisJson, tipo, clientId, isVideo}`. `gisJson` null o `clientId`
  vacío → el layer limpia.
- `segmento_media_item.dart`: `SegmentoMediaItem` gana `gisJson` (mapeado desde
  `ImagenSegmentoEntity`/`VideoSegmentoEntity`, ya lo traían).
- `segmento_detalle_page.dart` (`_MediaCarouselState`): dispatch de `mediaGisActivada` gateado a
  la pestaña visible vía `TabController` (`DefaultTabController.of(context)`, índices Antes=2/
  Después=3) — evita que el carrusel oculto (el `TabBarView` construye las 4 pestañas) pise el
  evento de la visible. Dispatch en el flanco de entrada a la pestaña y en cada `onPageChanged`.
- `presentation/detalle/media_gis_layer.dart` (nuevo): `MediaGisLayer` (StatefulWidget, hijo de
  `FlutterMap`) + `MediaGisLayerController` (controller plano, no GetX; `RxList` de
  `Marker`/`Polyline`). Foto → marker + flecha roja de dirección (si trae rumbo); vídeo → polyline
  azul de traza + marker de inicio. Insertado en `_MapaSegmento` tras el polyline del segmento
  destacado.

**`flutter analyze` → 0 issues. `flutter test test/core/gis/...` → 11/11 pass.**

### Incrementos del mismo día — encuadre automático, banda de dirección de vídeo, marker circular, migración a `ValueNotifier`

- **Encuadre automático del mapa:** nuevo `AppTypedActions.mediaGisBoundsRequested` —
  `TypedAction<LatLngBounds>` (bounds de `flutter_map`), emitido por `MediaGisLayerController`
  cuando calcula geometría para la media activa. `SegmentoDetalleController._fitMediaBounds` lo
  escucha y llama `mapController.fitCamera(CameraFit.bounds(bounds, padding:
  EdgeInsets.all(80), maxZoom: 17))` — encuadra la georreferencia con margen amplio sin que el
  usuario tenga que buscarla en el mapa.
- **Fix primer acceso al carrusel:** en `_MediaCarouselState` (`segmento_detalle_page.dart`), un
  tap directo de pestaña (0→2/3) mueve el `TabController.index` antes de que el `State` monte, así
  que `_onTab` se pierde el flanco de subida y el mapa no se actualiza la primera vez. Se añade un
  dispatch inicial post-frame cuando el carrusel monta ya activo.
- **Marker de foto/vídeo rediseñado:** círculo de color de 18px con borde blanco (mismo estilo que
  `MyCurrentLocationLayer`) en vez de un `Icon` grande. Color foto = rojo, color vídeo = morado
  (`deepPurpleAccent`) — elegido para no confundirse con el marker azul de ubicación actual.
- **Banda de dirección de cámara (vídeo):** `media_gis_map_geometry.dart` gana `VideoVertex`
  (punto + rumbo), `parseVideoTrack` (parsea `[lon,lat,alt,heading_deg,t]` conservando el rumbo por
  vértice) y `directionBandPolygon` (offsetea cada vértice del track ≈22 m hacia su rumbo de
  cámara, cierra el anillo `[track…, offset invertido]`; vértices sin rumbo heredan el del vecino;
  vacío si <2 vértices o sin rumbo alguno). Se pinta como `PolygonLayer` morado semitransparente
  **debajo** de la polyline del track — área rellena que muestra hacia dónde apuntó la cámara a lo
  largo de todo el recorrido. `parseVideoGis` pasa a ser un wrapper fino sobre `parseVideoTrack`.
- **Reactividad migrada de GetX a `ValueNotifier`:** `MediaGisLayer` (ahora `GetView`,
  `StatelessWidget`) renderiza con primitivas Flutter — `MediaGisLayerController` expone un único
  `ValueNotifier<MediaGisGeometry>` (snapshot inmutable: polígonos + polylines + markers) y el
  widget usa `ValueListenableBuilder` (sin `Obx`, un solo rebuild para las tres capas). El
  controller sigue siendo `MyGetxController` solo para DI + ciclo de vida `onTypedAction`
  (`onClose` libera el notifier). Dirección de proyecto: código reactivo nuevo usa
  `ValueNotifier`/`ValueListenableBuilder`, migrando gradualmente fuera de GetX (el
  `GetxController` se mantiene por ahora).
- Ficheros nuevos/tocados: `core/gis/media_gis_map_geometry.dart`,
  `presentation/detalle/media_gis_layer.dart`, `segmento_detalle_page.dart`,
  `segmento_detalle_controller.dart`, `segmento_detalle_binding.dart` (`lazyPut
  MediaGisLayerController`), `core/app_typed_actions.dart`,
  `test/core/gis/media_gis_map_geometry_test.dart` (+tests de `parseVideoTrack`/
  `directionBandPolygon`).

**Compila limpio, `flutter analyze` → 0 issues, 17/17 tests unitarios pasan.**

## 2026-07-10 — Fix: 2ª foto quedaba sin GIS (`gis_json` null, mapa en blanco)

**Síntoma:** la 1ª foto (antes/después) se georreferenciaba bien; la 2ª guardaba `gis_json` null
sin error y el mapa de detalle no pintaba nada. El vídeo no se veía afectado.

**Causa raíz:** `MediaGisRecorder.snapshotPhoto()` leía `_lastPosition` de forma instantánea, sin
fallback. `_lastPosition` sólo lo rellena el listener de `Geolocator.getPositionStream()`, que en
Android es un **broadcast cacheado y compartido por proceso**. La página de detalle monta siempre
`CurrentLocationLayer` (`MyCurrentLocationLayer`), que mantiene ese stream vivo. En la 2ª captura el
recorder se suscribe **tarde** a un broadcast en marcha, y un broadcast no reentrega su último valor
a un suscriptor tardío → `_lastPosition` seguía null al disparar → `snapshotPhoto()==null` →
`buildPhotoGeoJson(null)` devuelve null → se persiste null (fielmente; la persistencia no era el
problema). El vídeo es inmune porque `startTrack` muestrea 1/seg durante segundos → ≥1 muestra.

**Fix:** `snapshotPhoto()` pasa a `async`: si el stream aún no tiene fix, cae a
`getLastKnownPosition()` (instantáneo) y, si hace falta, a un `getCurrentPosition(timeout 4s)`, y
**loguea** (sin éxito silencioso). Nuevo flag `_locationGranted` para no intentar el fallback sin
permiso. `camera_capture_page._takePhoto` ahora `await _gis.snapshotPhoto()` (el obturador ya
mostraba spinner durante la espera). Ficheros: `core/gis/media_gis_recorder.dart`,
`presentation/camera/camera_capture_page.dart`. `flutter analyze` → 0 issues.

Diagnóstico corroborado por workflow multi-agente (3 lentes: captura/persistencia/render + verify
adversarial): persistencia y render exonerados; causa en la captura GIS.

## 2026-07-10 — `gis_json`: propiedad `source` (cámara vs galería)

Se añade a `properties` del `gis_json` (foto y vídeo) una propiedad **`source`** con valores
`"camera"` | `"gallery"`, para distinguir media capturada con la cámara de la app de la elegida de
la galería del dispositivo. Nuevo `enum MediaSource { camera, gallery }` (`media_gis_geojson.dart`,
`wireValue` = string).

**Cambio de contrato:** `buildPhotoGeoJson`/`buildVideoGeoJson` pasan de `String?` a `String` — ahora
**emiten siempre** un FeatureCollection. Sin muestra útil (galería, o captura sin fix GPS) el
`Feature` lleva **`geometry: null`** y las properties con `kind` + `source` + meta. Antes esa media
guardaba `gis_json = null` (indistinguible de "cámara sin fix"); ahora el origen se conoce siempre.
Los parsers (`parsePhotoGis`/`parseVideoTrack`) ya toleraban `geometry: null` → sin cambios.
`_addImagen`/`_saveVideoFromPath` reciben `required MediaSource source`; los 4 call sites de
`capturarMedia` pasan cámara/galería. Tests de `media_gis_geojson_test.dart` actualizados (9/9).
`flutter analyze` → 0 issues.

> **Backend:** el `gis_json` ahora puede llegar con `geometry: null` y siempre trae
> `properties.source`. Reflejar en `docs/BACKEND_SYNC_CONTRACT.md` al cerrar la migración.

## 2026-07-10 — Editar extremos solo en estado "contratista"

El botón **Editar extremos** (tab detalle) se muestra solo cuando `segmento.estado ==
EstadoActividad.contratista` — el estado en que el operario de campo trabaja la tarea. Gate sobre el
estado **persistido** del segmento (no el dropdown editable sin guardar). `_GuardarBar` sigue
autónomo; lee el estado vía `Get.find<SegmentoDetalleController>()`. Fichero:
`segmento_detalle_page.dart`.

## 2026-07-16 — Envío por segmento reordenado: segmento primero, id propagado a hijos

**Motivo:** un segmento creado en la app (no traído del pull) no tiene `id` de backend hasta que se
sube. Los adapters de imagen/vídeo/mensaje envían el `id` numérico leído de `entity.segmentoId` —
si esos hijos se subían ANTES que el segmento (orden previo: vídeo → foto → mensaje → segmento),
subían con `segmento_id` a 0/null y quedaban sin vincular en el backend.

**Cambio:** `ForzarEnvioController._sendOne` ahora drena `segmento` PRIMERO. Si el drain no es
limpio (rejected/retryable/conflicts/authExpired) se corta sin tocar hijos. Si es limpio, relee el
segmento del store local por `clientId` (`SegmentoLocalStore.findByClientId`) para obtener el `id`
que el engine acaba de persistir (`UpdateLocalStateTask` → `markSynced` ya lo escribe sin cambios en
el motor) y lo propaga con el nuevo `PropagateSegmentoRemoteIdUseCase` a las columnas `segmento_id`
de `imagenes_segmento`/`videos_segmento`/`mensajes_segmento` (match por `segmento_client_id`, una
sola transacción) ANTES de drenar vídeo → foto → mensaje.

`SegmentoRemoteAdapter` pasa de dos endpoints (`create`/`update/{id}`) a un único upsert: `POST
/segmentos/upsert` con `segmento_id` en el body (`null` si es alta, el id existente si es
actualización); el backend decide insertar o actualizar. Ya acepta `SyncOperation.create` además de
`update` (antes `create` devolvía `SyncUnrecoverable`). Los antiguos `ApiEndpoints.segmentoUpd`/
`segmentoAdd` se eliminan (sin más referencias tras el cambio).

Ficheros: `core/api_endpoints.dart` (nuevo `segmentoUpsert`, eliminados `segmentoUpd`/`segmentoAdd`),
`data/sync/segmento_remote_adapter.dart` (upsert único), `data/sync/propagate_segmento_remote_id_usecase.dart`
(nuevo), `data/sync/imagen_local_store.dart`/`video_local_store.dart`/`mensaje_local_store.dart`
(nuevo `setSegmentoRemoteId`), `presentation/forzar_envio/forzar_envio_controller.dart` (orden de
`_sendOne` + nuevas deps `PropagateSegmentoRemoteIdUseCase`/`SegmentoLocalStore`),
`test/presentation/forzar_envio/forzar_envio_controller_test.dart` (orden y 2 tests nuevos: guard de
segmento no-limpio, backendId ausente). `flutter analyze` → 0 issues; 49/49 tests de los ficheros
tocados pasan.

---

## 2026-07-18 — Cumplimiento de spec `BACKEND_SEGMENTO_SYNC_ENDPOINTS.md` (12 fixes)

Verificación del cliente contra la spec (única fuente de verdad; `CLIENT-VIDEO-UPLOAD.md` y
`BACKEND_VIDEO_CONTRACT.md` estaban obsoletos y el backend los borró). 33 mismatches confirmados tras
refutación adversarial; se aplicaron los de cliente. `flutter analyze` → 0 issues; 519 tests pasan.

**Media (§9) — BLOCKER, ninguna foto/vídeo de nube cargaba.** Dos defectos apilados: la URL se
construía sobre `ApiEndpoints.baseUrl` (host pelado, sin `/api/enagas/v1` → 404) y sin credencial
(→ 401). Fix: `ApiEndpoints.segmentoThumb(id,w,h)` (endpoint único de media; `/segmentos/imagen` y
`/videos/download` RETIRADOS), `ApiSecurityService.buildSignedMediaUrl(path)` (firma en query
`?ts=&sig=`, ventana 2h, cubre SOLO el pathname). Fotos → HMAC en cabeceras; vídeo → firma en query
(el `<video>` fija la URL y el seek reusa el `ts`; ±5 min no aguanta). `status` de vídeo se parsea y
la reproducción se bloquea salvo `disponible` (`convirtiendo`→"procesando", 404 evitado).

**Sobre del segmento (§2) — BLOCKER, pérdida silenciosa de vídeo de campo.** La unidad de sync es el
SOBRE entero, no el adjunto: hasta el 200 de `sync-complete` todo hijo es `pending` y un `upsert`
nuevo anula el intento anterior (el backend borra sus `pending`). El motor marcaba `synced` cada job
por separado, así que un vídeo ya subido no se reenviaba tras un `upsert` que lo había borrado en
servidor → la purga borraba la fila y el fichero local. Fix en el controller (que SÍ sabe que se
entregó un upsert): `VideoLocalStore.clearUploadSessions(segmentoClientId)` antes del re-drain, así el
adapter reinicializa sesión y resube los bytes. Resume dentro de un mismo intento intacto.

**upsert (§3):** el body omitía 10 campos declarados (`tipo_actividad`, `descripcion`, `nombre`,
`traza`, `tipo_instalacion`, `pk_inicio`, `pk_fin`, `fecha_inico` [SIC, nombre real de columna],
`fecha_fin`, `longitud`) → el backend los descartaba en silencio (ajv `removeAdditional:"all"`, 200).
Ahora se mandan todos. Quitados `client_id`/`usuariologged`/`idusuariologged` (no declarados).

**401 nunca es logout (§1):** `sync_outcome_from_network_error` y los fetchers mapeaban 401 →
`AuthExpiredException` → wipe de token + navegación a login. En esta API no hay sesión ni Bearer: 401 =
fallo de firma HMAC (secreto mal, reloj desviado >5 min, path mal firmado). Ahora → `SyncUnrecoverable`
sin logout.

**Vídeo (§6):** `tipoFoto` ahora viaja en el init (antes todo vídeo "antes" se guardaba `despues`); el
409 sin clave `error` se trata como señal de REANUDAR (chunk y complete) parseando `offset`, con guarda
de progreso acotado; se persiste el `id` que devuelve `complete`; se retira el sellado con
`/videos/download`.

**Mensaje (§5):** la respuesta ya no pasa por `fromJson` (acuñaba un `clientId` nuevo → fila local
huérfana duplicada); se estampa solo el `id` entero sobre la entidad existente. Body recortado a
`mensaje`+`enviado_por`.

**imagen (§4):** `subida_por` manda el id entero, no el nombre de usuario; quitado el header Bearer
muerto (y su dependencia `flutter_secure_storage`).

**Finalize atascado (§7):** un segmento en `finalizeFailed` (todo `synced`, solo falló el POST de
`sync-complete`) quedaba excluido de "Enviar todos" para siempre. Ahora se reintenta (sync-complete es
idempotente y no destructivo); no revoca sesiones de vídeo (no se entrega upsert nuevo).

**Docs mentirosos / dead code:** comentarios que afirmaban eco de `client_id`, Bearer token, o 401 =
sesión, corregidos. `ApiEndpoints.baseUrl` (sin consumidores) eliminado. `AuthExpirationHandler`:
solo documentado como inalcanzable — su borrado (handler + registro DI + tipo `AuthExpiredException`)
queda PENDIENTE de sign-off.

**PENDIENTE de decisión del responsable:**
1. `ctname` en `upsert`: la spec §3 lo declara pero `SegmentoEntity` no tiene el campo (solo `ctId`).
   En insert el segmento aterriza con `ctname` NULL y §8 filtra `?cts=` por nombre → el segmento nuevo
   nunca vuelve en la descarga. Cerrarlo exige columna + campo + migración schema 1→2 + poblarlo del
   `ctname` que §8 ya devuelve. ¿Lo deriva el backend en insert, o lo manda el cliente?
2. Borrado de `AuthExpirationHandler` (arriba).

### 2026-07-18 (cont.) — `SegmentoEntity`: identidad de CT por `ctname`, no `ctId`

Decisión del responsable: el segmento identifica su CT por **`ctname` (String)**, como
`PosicionFijaEntity`, no por `ctId` (int). Alinea con el contrato: §3 (upsert) y §8 (descarga
contratista) usan `ctname` y §8 filtra por NOMBRE de CT. Arregla además un bug latente: la descarga
`/segmentos/contratista` devuelve `ctname` pero `fromJson` leía `ct_id` → todo segmento descargado
quedaba con `ctId=0`.

`SegmentoLocalStore` schemaVersion **1→2** (columna `ct_id INTEGER` → `ctname TEXT NOT NULL DEFAULT ''`,
índice `idx_segmentos_ct`→`idx_segmentos_ctname`; migración DROP+CREATE porque la app es pre-release,
sin back-compat). El body del upsert ya manda `ctname` (cierra el último campo pendiente de §3).

Ruta de lectura migrada por necesidad (consultaba la columna eliminada): `findByCts(List<int>)`→
`findByCtNames(List<String>)`, `getByOperador`, y `GetSegmentosUseCase` ahora lee NOMBRES de CT de
`user_json` (misma fuente que `SegmentoRemoteFetcher` usa para la descarga §8 — lectura local y
descarga filtran de una fuente consistente). El nombre en el punto de creación sale del hit del mapa
(`GasoductoHitData.ct`, poblado del mapa id→nombre del usuario) vía nuevo `PolylineSegment.ctname`.

NO tocados (correcto): `HitoEntity`/`PkEntity`/`GasoductoEntity` y sus tablas conservan su propio
`ctId`; `GasoductoHitData.ctId` y `PolylineSegment.ctId` los sigue usando el motor de corte de líneas.

`flutter analyze` → 0 issues; 521 tests pasan (verificado de forma independiente). Consumidores de
`SegmentoEntity.ctId` migrados: `app_di`, `mapa_global_controller`, `forzar_envio` (filtro por nombre),
`segmento_detalle_controller`, `segmento_list_card_widget`, `segmentos_list_controller` (agrupa por
nombre). Docs: `ARCHITECTURE_REFERENCE.md` actualizado.

---

## 2026-07-20 — Nuevo catálogo de `TipoActividad` (11 tipos, sin mapeo legacy)

Sustitución completa del enum `TipoActividad` (`lib/domain/entities/segmento_entity.dart`). Los 7
valores anteriores se eliminan **sin mapeo legacy**: `deshierbe_posiciones`, `deshierbe_selectivo`,
`desratizacion` y `tala_arboles` desaparecen y cualquier string desconocido cae al default vía el
`orElse` de `fromString`.

Nuevos wire values (snake_case, campo `tipo_actividad`), agrupados por ámbito:

- Gasoducto: `desbroce_manual`, `desbroce_mecanico`, `tala`, `resiembre`.
- Gasoducto + posición: `posicion_desherbaje_traza` (**nuevo default** de `fromString`, sustituye a
  `deshierbe_selectivo`).
- Posición: `trat_avispas`, `trat_aranas`, `trat_reptiles` y sus variantes con otros tratamientos
  `trat_avispas_otros`, `trat_aranas_otros`, `trat_reptiles_otros`.

Propagado a los 5 mapas de color (`_tipoFilterColors` / `_tipoColors` en `mapa_global_page`,
`forzar_envio_page` ×2, `segmentos_list_page` ×2) con paleta de 11 entradas, y a todos los usos de
`TipoActividad.desherbajeSelectivo` → `TipoActividad.posicionDesherbajeTraza` en lib/ y test/.

**Pendiente:** confirmar con backend que acepta estas claves en `tipo_actividad`. El DEFAULT SQL de la
columna en `SegmentoLocalStore` sigue siendo `'deshierbe_selectivo'` (string ya inexistente en el enum;
inocuo porque `fromString` lo resuelve al default, pero conviene alinearlo en la próxima migración de
schema).
