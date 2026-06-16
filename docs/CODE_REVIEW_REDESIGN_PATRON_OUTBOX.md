# Informe de revisión de código — rama `REDESIGN-PATRON-OUTBOX` (v2, verificado)

**Fecha:** 2026-06-16 · **v1:** 2026-06-15 (revisión inicial) · **v2:** re-verificación adversaria contra el código real + barrido de omisiones.
**Alcance:** `git diff main...HEAD` — rediseño del motor offline-first (outbox, engine, pull, tasks, stores, adapters, repos, UI de sincronización/mapa). ~5.800 inserciones / ~2.470 borrados en `lib/`.
**Método v2:** cada hallazgo de v1 pasado por un verificador adversario que leyó el código real (no el diff), citando la línea decisiva; + 6 barridos de recall sobre áreas que v1 no cubrió (pull coordinator, GPS, repos/mensaje, DB/DI, UI sync, flujo de captura). Todas las líneas citadas verificadas en el working tree. `dart analyze` = 0 errores (3 lints `avoid_print`).

> **Qué cambió respecto a v1** (resumen al final, sección K): 8 hallazgos confirmados, 6 corregidos en severidad o mecanismo (2 sobrevalorados → bajados; varias localizaciones erróneas corregidas), y **25 hallazgos nuevos** — entre ellos un clúster crítico que v1 no vio: **el pipeline de pull reporta éxito ante fallos parciales/bloqueantes**.

---

## A. Rúbrica de severidad

| Nivel | Criterio |
|---|---|
| 🔴 Crítico | Crash, cuelgue permanente, o pérdida de datos sin feedback. **Bloquea merge.** |
| 🟠 Alto | Pérdida/corrupción silenciosa de datos o estado, o violación del contrato offline-first, en ruta alcanzable. |
| 🟡 Medio | Bug correcto pero de alcance limitado, o que solo se vuelve grave al desplegar. |
| ⚪ Bajo / Limpieza | Cosmético, código muerto, ineficiencia acotada, o latente sin trigger actual. |

---

## B. Resumen ejecutivo

El rediseño está bien estructurado (pipeline por job, schema modular por entidad, contratos limpios) pero comparte un **anti-patrón sistémico**: tareas no bloqueantes (`isBlocking=false`) y `catch → debugPrint` que **enmascaran fallos mientras la UI muestra verde**. Combinado con dos cadenas de fallo concretas, produce cuelgue + pérdida de datos que el operario no puede detectar.

**Cadena 1 — cuelgue de sincronización + brick del motor:**
```
isConnected = true (hardcoded, #6)  →  sync arranca sin red
        ↓
jobs fallan como retryable          →  drain() bucle infinito (#1)
        ↓                               _isDraining queda true → TODO drain futuro es no-op (brick permanente)
pull machaca ediciones (#2)         →  genera jobs huérfanos que alimentan el bucle
```

**Cadena 2 — éxito silencioso ante fallo (sección F, nueva):** pull y master-data reportan "descargado OK / hace X min" aunque el backend falló, la transacción abortó, o solo se sirvió la caché. El operario cree que tiene datos frescos cuando están vacíos o caducos.

**Dependencia de backend que desbloquea 2 bugs cliente:** #2 (re-mint de UUID en segmentos) y NF-18 (mensajes duplicados) comparten raíz — `fromJson` acuña un UUID nuevo cuando el backend omite `client_id`. El contrato de backend (`client_id` idempotente, eco en respuestas) resuelve ambos; hasta entonces se necesita el puente defensivo en cliente.

---

## C. Tabla maestra de hallazgos

| # | Sev | Verdict | Localización (verificada) | Problema |
|---|---|---|---|---|
| 1 | 🔴 | CONFIRMED | `sync_engine.dart:83-157` (+ `outbox_queue.dart:125-140`) | `drain()` bucle infinito; `_isDraining` queda `true` → brick permanente |
| 2 | 🔴 | CONFIRMED | `segmento_local_store.dart:59-72` (+ `segmento_entity.dart:120`) | Pull re-acuña UUID → borra fila editada + huérfanos en outbox |
| 3 | 🔴 | CONFIRMED | `main.dart:7-8` (+ `initializer_controller.dart` muerto) | `AppDI.init()` sin `await` → crash de arranque |
| NF-1 | 🔴 | NEW | `pull_coordinator.dart:87` | Fallo bloqueante de pull se reporta como éxito vacío; `pull_state` no se escribe |
| NF-P | 🔴 | NEW | `segmento_detalle_controller.dart:261` | `_addImagen` descarta la foto si `segmento.id==null`, sin feedback |
| 4 | 🟠 | CONFIRMED | `segmento_detalle_controller.dart:351-354` | `guardar()` descarta edición local-only + toast de éxito falso |
| NF-11 | 🟠 | NEW | `segmento_repository_impl.dart:80` | `updateEstado` solo `findByRemoteId` → estado de segmento local-only nunca persiste |
| 6 | 🟠 | PARTIAL | `connectivity_service.dart:12` | `isConnected` hardcoded `true` → **4** guardas offline muertas |
| NF-2 | 🟠 | NEW | `upsert_non_conflicting_task.dart:30` | Fallo en un ítem aborta el bucle (no bloqueante); pull parcial reportado OK |
| NF-3 | 🟠 | NEW | `enqueue_conflicts_task.dart:41` | Fallo al insertar conflicto se traga; "ok_with_conflicts" sin filas |
| NF-7 | 🟠 | NEW | `gps_background_service.dart:140` vs `:150` | `_buffer.clear()` antes de `await create()` → batch perdido si la escritura falla |
| NF-8 | 🟠 | NEW | `gps_background_service.dart:256` | `onClose()` hace `unawaited(stop())` → último tramo GPS perdido |
| NF-10 | 🟠 | NEW | `segmento_local_store.dart:152-175` | `_entityToRow` omite `synced_at` + `replace` → `synced_at`=NULL en cada edición |
| NF-12 | 🟠 | NEW | `gasoductos_service.dart:144`, `pks_service.dart:123` | `_runOnce` traga toda excepción → descarga fallida reportada como éxito |
| NF-16 | 🟠 | NEW | `mensaje_segmento_repository.dart:68` | Fallback offline solo `on NetworkError` → cache no servida en otros errores |
| NF-19 | 🟠 | NEW | `offline_database.dart:33-48` | `migrateEntity` sin transacción → migración parcial brickea el arranque |
| NF-9 | 🟠 | NEW | `gps_background_service.dart:202` | `_readOperadorId` → `?? 0` atribuye el batch a operador inexistente |
| 5 | ⚪ | PARTIAL | `segmento_remote_adapter.dart:73` (+ mapper `:29`) | Conflicto en **push** muerto (409→rejected). Pull sí usa la maquinaria |
| 7 | ⚪ | CONFIRMED | `auth_expiration_handler.dart:42-60` | Guard re-entrante mal reseteado → logout/snackbar duplicado |
| NF-4 | 🟡 | NEW | `detect_conflicts_task.dart:61-70` | `_pendingClientIds` ignora estado `syncing` → pull pisa edición en vuelo |
| NF-5 | 🟡 | NEW | `update_pull_state_task.dart:27-39` | No puede representar un pull degradado (sin estado `error`/`partial`) |
| NF-6 | 🟡 | NEW | `dispatch_pull_completed_task.dart:20` | Dispatch de "completado limpio" tras fallo no bloqueante |
| NF-13 | 🟡 | NEW | `sincronizacion_controller.dart:184,195` | Cancel no llega a `gasoductos/pks.reload()` (la descarga más larga) |
| NF-14 | 🟡 | NEW | `sincronizacion_controller.dart:243` (+ `gasoductos_service.dart:102`) | "Descargado ahora" falso cuando hubo short-circuit a caché |
| NF-15 | 🟡 | NEW | `sincronizacion_controller.dart:62/137` | `_initRows()` no `await`-eado → `StateError` si se toca antes de cargar prefs |
| NF-17 | 🟡 | NEW | `mensaje_segmento_repository.dart:62` | Cache vacía → `failure(503)` en vez de éxito vacío |
| NF-18 | 🟡 | NEW | `mensaje_segmento_repository.dart:105` | Dedup por `clientId` roto cuando backend omite `client_id` → mensaje duplicado |
| NF-20 | 🟡 | NEW | `app_di.dart:29` | `AppDI.init()` no idempotente → doble llamada crashea (`StateError`) |
| NF-21 | 🟡 | NEW | `outbox_queue.dart:29-42` | `enqueue` con `replace` borra `remote_id` al re-encolar op ya sincronizada |
| A3 | 🟡 | CONFIRMED | `local_database.dart:68-98` | `gasoductos`/`pks` sin mecanismo de migración (grave al desplegar) |
| A4 | 🟡 | PARTIAL | `imagen_local_store.dart:32`, `mensaje_local_store.dart:26` | FK por id remoto, no `client_id`; hoy se manifiesta como no-op silencioso |
| A5 | ⚪ | PARTIAL | `syncable.dart:8` + stores `markSynced` | `remoteId` String vs INTEGER; `int.tryParse` descarta en silencio |
| A6 | ⚪ | PARTIAL | `gps_background_service.dart:138-141` | `startedAt`(reloj sistema) vs `endedAt`(reloj GPS) → intervalo invertido; sin UTC |
| 8 | ⚪ | CONFIRMED | `imagen_repository_impl.dart:28-38` | Full-table scan por apertura de detalle; `getPendingBySegmento` muerto |
| 9 | ⚪ | CONFIRMED | `sync_engine.dart:111-119` | `TaskPipeline` reconstruido por cada job |
| 10 | ⚪ | CONFIRMED | `detect_conflicts_task.dart:45` | N+1 `findByClientId` por ítem (típico N+C, peor caso 2N) |
| A1 | ⚪ | CONFIRMED | adapters/stores | Duplicación `_authHeader`/`markSynced`/extracción remote-id (esta última diverge) |
| A2 | ⚪ | PARTIAL | `imagen_repository_impl.dart:45` | `uploadPending(int)` ignora el parámetro; `UploadImageUseCase` muerto |
| NF-22 | ⚪ | NEW | `app_router.dart:74` | `AuthMiddleware.redirect` siempre `null` → rutas "protegidas" no lo están |
| NF-23 | ⚪ | NEW | `position_local_store.dart:148-165` | `findAll()` N+1 (una query de puntos por batch) |
| NF-24 | ⚪ | NEW | `position_local_store.dart:211` | `updated_at` corrupto → se fabrica `DateTime.now()` |
| NF-25 | ⚪ | NEW | `imagen_remote_adapter.dart:64` | Sniff MIME con `openRead().first` puede mal-etiquetar PNG como JPEG |
| DC | ⚪ | — | varios | Código muerto: `SyncJobResult.pending` (`sync_engine.dart:154`), `InitializerController`, `UploadImageUseCase`, mixin legacy |

---

## D. Críticos (bloquean merge) — detalle + repro

### 1. 🔴 `drain()` bucle infinito + brick permanente del motor — `sync_engine.dart:83-157`

`drain()` itera `while(true)` re-consultando `nextPending(status='pending')` (`:84`), solo rompe en `if (batch.isEmpty)` (`:88`). Un `SyncRetryable` (o cualquier fallo de pipeline no-auth) llama a `markPendingAgain` (`:137` / `update_local_state_task.dart:53`), que en `outbox_queue.dart:125-140` **devuelve `status='pending'` y no toca `created_at`** → `nextPending` (orderBy `created_at ASC`) devuelve el mismo job primero en la siguiente iteración. Ningún `attempts` se consulta como condición de parada.

`syncOutcomeFromNetworkError` mapea `offline`/`timeout`/`5xx`/`429` → `SyncRetryable`, así que **sin red o con backend caído, cada intento es retryable → bucle infinito determinista**.

**Peor que un spinner colgado:** `_isDraining` solo se pone `false` en el `finally` (`:158-159`), que nunca se alcanza → **todo `drain()` futuro de la sesión sale en seco** por la guarda de `:79`. El motor queda inutilizado.

> Corrección a v1: la afirmación "el mismo job se reintenta dentro del bucle" es imprecisa — el `for` interno recorre el `batch` snapshot una vez; el reintento infinito ocurre **entre** iteraciones del `while`. No cambia el veredicto.

**Repro:** modo avión → pantalla con cualquier job pendiente → disparar `drain` (vía upload de imagen, único entry-point que hoy lo invoca) → cuelgue; el resto de la sesión no sincroniza.

**Fix (el de v1 es incompleto):** un "procesa un batch y sal" deja jobs sin procesar cuando `pending > limit(100)`. Opciones correctas: (1) trackear ids ya intentados en un `Set<int>` dentro de `drain()`, descartarlos del batch, romper cuando el filtrado quede vacío; **o** (2) introducir un estado transitorio `retryable`/`failed` para que `nextPending` no pueda re-devolver un job recién fallado (más limpio; además distingue retryable de nunca-intentado). En ambos casos, **garantizar el reset de `_isDraining`** y guardar el call-site contra offline.

---

### 2. 🔴 Pull machaca ediciones locales + huérfanos — `segmento_local_store.dart:59-72`

`SegmentoEntity` (`:120`): `_clientId = clientId ?? const Uuid().v4()`; `fromJson` lee `client_id` y lo pasa (`:176-180`). **El backend no devuelve `client_id` hoy** → cada pull acuña un UUID nuevo. Schema: `client_id TEXT PRIMARY KEY` + `CREATE UNIQUE INDEX idx_segmentos_remote ON segmentos(id) WHERE id IS NOT NULL` (`:59-62`).

`DetectConflictsTask:45` hace `findByClientId(nuevoUuid)` → `null` → `safeToUpsert` → `upsert` con `ConflictAlgorithm.replace` (`:72`). SQLite `INSERT OR REPLACE` borra TODA fila que choque en cualquier constraint único, **incluido el índice parcial** → la fila local (id remoto no nulo, con la edición del operario) se borra y se reinserta la remota con otro `client_id`. El job de outbox queda keyed al UUID viejo → siguiente drain `LoadEntityTask` → `findByClientId(viejo)`=null → `StateError` → alimenta #1.

**Precondición = secuencia offline-first normal:** pull → editar offline → volver a pull. No es un estado raro.

**Repro:** "Descargar" segmentos → editar uno offline (queda job pendiente) → "Descargar"/"Preparar campo" otra vez → la edición desaparece y el motor empieza a colgarse.

**Fix (el de v1 es incompleto):** resolver identidad por `findByRemoteId` (existe en `:128`) **y además** (a) reusar el `clientId` local existente antes del upsert para que el índice parcial no dispare REPLACE, y (b) seguir enrutando a **conflicto** (no `safeToUpsert`) si esa fila tiene job pendiente o `localUpdatedAt > remoteUpdatedAt`. Belt-and-suspenders: quitar `ConflictAlgorithm.replace` para que una violación UNIQUE aflore en vez de borrar en silencio. **Fix de fondo:** backend debe devolver `client_id` estable (desbloquea también NF-18).

---

### 3. 🔴 `AppDI.init()` sin `await` — `main.dart:7-8`

```dart
//await AppDI.init();
AppDI.init().then((_) => print("✅ AppDI Cargado"));
runApp(const MainApp());
```

`main()` no es `async`; init es fire-and-forget. `main_app.dart:17` fija `initialRoute: AppRoutes.login`. El login toca DI síncronamente en construcción: `login_page_controller.dart:8` `final _repo = AuthRepositoryImpl();` → `auth_repository_impl.dart:9` `AuthDataProvider()` → `auth_data_provider.dart:8` `final NetworkService _network = Get.find<NetworkService>();` (inicializador de campo, corre en construcción). `AppDI.init()` registra `NetworkService` tras un `putAsync` + apertura SQLite con timeout de hasta 15s → si el primer frame gana la carrera: `'NetworkService not found'` → crash. Casi seguro en primer arranque (creación de DB) / dispositivos lentos.

**Fix:** restaurar `await AppDI.init();` (es literalmente la línea 7 comentada). `InitializerController` (`:15`) **ya implementa el gate correcto** pero es **código muerto** — cablearlo como ruta inicial con splash, o borrarlo. Su `catch` solo hace `print(e)` sin UI (NF: fallo de init = pantalla congelada sin feedback). Quitar el `print` (lint).

---

### NF-1. 🔴 Pull reporta éxito ante fallo bloqueante — `pull_coordinator.dart:87`

Una excepción no-401 de una tarea bloqueante (`InvokeRemoteFetcherTask`/`DetectConflictsTask`, `isBlocking=true`) se envuelve en `PipelineFailure`, no se relanza: el check `is AuthExpiredException` (`:66`) y el `on AuthExpiredException` (`:76`) no aplican → cae a `:87` y devuelve `PullSummary(total:0, …)` — **idéntico a un éxito vacío real**. Como la tarea abortó antes de `UpdatePullStateTask`, `pull_state` no se escribe → la página de sync muestra "última descarga OK / hace X min" mientras el backend falló. Datos de campo caducos creídos frescos.

**Fix:** propagar el fallo de tarea bloqueante (distinguir de éxito vacío) y escribir un `pull_state` de error explícito.

---

### NF-P. 🔴 `_addImagen` descarta la foto si `id==null` — `segmento_detalle_controller.dart:261`

```dart
final segId = segmento.id;
if (segId == null) return;   // antes de construir la entidad / saveLocal / enqueue
```

Operario abre el detalle de un segmento local-only (`id` remoto aún null) → "Capturar foto" → la cámara escribe el archivo a disco → `_addImagen` hace `return` **antes** de insertar fila, crear job de outbox o mostrar error. **La foto se pierde sin feedback.** Mismo gate `id==null` que #4 (mismo controlador, dos métodos).

**Fix:** persistir por `clientId` (no por id remoto) o, como mínimo, mostrar snackbar de error en vez de `return` silencioso. Envolver `saveLocal` en try/catch con feedback (hoy `_addImagen` no tiene manejo de error — una excepción de DB se propaga sin que el usuario lo sepa).

---

## E. Altos — detalle

### 4. 🟠 `guardar()` descarta edición local-only + toast falso — `segmento_detalle_controller.dart:351-354`
Tras escribir `estado/tipoActividad/descripcion` en `segmento` (`:348-350`), envuelve `saveLocal`+`updateEstado` en `if (segmento.id != null)` pero **siempre** muestra "Cambios guardados correctamente". Segmentos creados en campo (id null, alcanzables vía map-tap → `segmentos_map_controller.dart:80` → detalle) pierden la edición en silencio.
**Fix:** `saveLocal` **incondicional** (`segmento_repository_impl.dart:60-64` ya ramifica `create`/`update` según `id==null`); `updateEstado` solo si `id!=null` (o eliminarlo: es redundante, `saveLocal` ya escribe `estado`).

### NF-11. 🟠 `updateEstado` solo `findByRemoteId` — `segmento_repository_impl.dart:80`
`WHERE id = ?` → un segmento local-only nunca encuentra fila → 404. Compone con #4. **Fix:** resolver por `clientId` cuando `id==null`.

### 6. 🟠 `isConnected` hardcoded — `connectivity_service.dart:12` (PARTIAL — alcance ampliado)
`bool get isConnected => true;//_isConnected.value;`. **Corrección a v1:** no es "ningún consumidor lo lee" — el observable sí dirige los TypedActions `connectionLost/Restored` (la página de sync se autocorrige en el siguiente cambio de red), pero hay **4** guardas imperativas muertas, no 1: `sincronizacion_controller.dart:85` y `:108`, `gasoductos_service.dart:102`, `pks_service.dart:85`, `json_loader_service.dart:85`. **Fix:** descomentar `_isConnected.value`; regression-check de las 3 guardas de master-data que se re-activan.

### NF-2 / NF-3. 🟠 Tareas de pull no bloqueantes tragan errores → pull parcial reportado OK
`UpsertNonConflictingTask` (`isBlocking=false`, `:16`): un throw en el ítem N aborta el bucle, ítems N..fin no persisten, `ctx.upserted` parcial, pero `UpdatePullStateTask` escribe `'ok'`. `EnqueueConflictsTask` (`isBlocking=false`, `:24`): fallo de `db.insert` se traga; "ok_with_conflicts" sin las filas en `sync_conflicts` → conflictos invisibles e irresolubles. **Fix:** hacer bloqueantes estas tareas, o recolectar y reportar los errores tragados.

### NF-7 / NF-8. 🟠 Pérdida de tramos GPS — `gps_background_service.dart`
NF-7 (`:140` vs `:150`): `_buffer.clear()` **antes** de `await _offline.create(batch)`; si la escritura falla, el `catch` (`:152`) solo loguea → batch perdido sin re-encolar. NF-8 (`:256`): `onClose()` hace `unawaited(stop())`; `stop()` espera el flush final (transacción DB) que puede no completar antes del dispose → hasta ~30s de track perdidos al salir del mapa. **Fix:** escribir-luego-limpiar; `await stop()` en `onClose`.

### NF-10. 🟠 `synced_at` se borra en cada edición — `segmento_local_store.dart:152-175`
`_entityToRow` omite `synced_at` y `upsert` usa `replace` → cada edición local borra-reinserta la fila sin `synced_at` → NULL. Corrompe cualquier distinción synced-vs-dirty y el GC `purgeSynced`. Mismo bug (🟡) en `mensaje_local_store.dart`. **Fix:** incluir `synced_at` en `_entityToRow`.

### NF-12. 🟠 `gasoductos/pks._runOnce` tragan excepciones → éxito falso — `gasoductos_service.dart:144`, `pks_service.dart:123`
`catch → debugPrint`, retorna normal → `sincronizacion_controller._runOne` marca la fila verde con timestamp fresco. Un 500/parse-error en "Descargar" se reporta como éxito → mapa sin trazas/PKs en campo, el operario nunca reintenta. **Fix:** propagar la excepción para que `_runOne` la capture.

### NF-16. 🟠 Fallback offline de mensajes incompleto — `mensaje_segmento_repository.dart:68`
La caché solo se sirve `on NetworkError`; un `DioException` crudo / TLS / parse cae al `catch` genérico y devuelve `failure(500)` sin servir local → viola lectura offline-first. **Fix:** servir caché en cualquier fallo de red.

### NF-19. 🟠 `migrateEntity` sin transacción — `offline_database.dart:33-48`
`store.migrate()` + `_writeVersion()` sin `db.transaction`. Una migración multi-statement matada a medias commitea schema parcial con la versión sin subir → siguiente arranque re-aplica `ALTER TABLE` (sin IF NOT EXISTS) → "duplicate column" brickea el arranque. Sobrevive hoy solo porque todo `CREATE` usa IF NOT EXISTS. **Fix:** envolver en `db.transaction`.

### NF-9. 🟠 `_readOperadorId → ?? 0` — `gps_background_service.dart:202`
`user_id` ausente (race de logout) → batch atribuido a operador 0, persistido y enviado a `POST /positions/batch` bajo operador inexistente. **Fix:** abortar tracking si no hay operador válido.

### A4 (image FK). 🟠 FK de imagen por id remoto, no `clientId` — `segmento_detalle_controller.dart:259`
`ImagenSegmentoEntity.segmentoId:int` = id remoto; el adapter lo envía como `'segmentoId': entity.segmentoId.toString()`. Viola "las FKs viajan por clientId". Hoy se manifiesta como no-op silencioso (los productores guardan en `id==null`), pero impide adjuntar fotos a un segmento sin id remoto. **Fix completo** (refactor): `segmentoId` a `String(clientId)` en entidad+store+adapter+backend.

---

## F. 🔆 Clúster sistémico: "éxito silencioso ante fallo" (v1 no lo vio)

Tema transversal — `isBlocking=false` + `catch → debugPrint` que reportan verde mientras los datos están vacíos/parciales/caducos. Es el espejo de #1 ("drain oculta el fallo offline"). Componentes: **NF-1, NF-2, NF-3, NF-12, NF-14**, y estructuralmente **NF-5** (el estado de pull no puede representar "error"/"partial": `update_pull_state_task.dart:27-39` siempre escribe `last_error:null` y status en `{ok, ok_with_conflicts, cancelled}`) y **NF-6** (`dispatch_pull_completed_task.dart:20` dispara "completado limpio" siempre). **Recomendación arquitectónica:** introducir un estado `error`/`partial` en `pull_state` + un campo de error, y una política explícita de "tarea no bloqueante que falla debe registrar el fallo agregado al final del pipeline". Sin esto, el indicador "última descarga" que el operario usa para confiar en sus datos es estructuralmente incapaz de mostrar degradación.

---

## G. Medios y bajos (follow-up)

- **NF-4** 🟡 `detect_conflicts_task.dart:61-70` — `_pendingClientIds` consulta solo `pending`+`rejected`, no `syncing`; un pull concurrente con un drain en vuelo clasifica el clientId como `safeToUpsert` → `upsert(replace)` pisa la edición que se está enviando. **Fix:** incluir `syncing`.
- **NF-13** 🟡 `sincronizacion_controller.dart:184,195` — Cancel solo llega a `runPull('segmento')`; `gasoductos/pks.reload()` no reciben token → Cancel no-op en la descarga más larga.
- **NF-14** 🟡 `sincronizacion_controller.dart:243` + `gasoductos_service.dart:102` — fila marcada "success" con timestamp fresco aunque `reload()` haga short-circuit a caché (sin fetch).
- **NF-15** 🟡 `sincronizacion_controller.dart:62/137` — `_initRows()` async no `await`-eado; tocar descarga antes de cargar prefs → `firstWhere` `StateError` sin guardar.
- **NF-17** 🟡 `mensaje_segmento_repository.dart:62` — caché vacía → `failure(503)` en vez de éxito vacío; el operario no distingue "sin mensajes" de "error de red".
- **NF-18** 🟡 `mensaje_segmento_repository.dart:105` — dedup por `clientId` roto cuando backend omite `client_id` (misma raíz que #2) → mensaje duplicado.
- **NF-20** 🟡 `app_di.dart:29` — `init()` no idempotente; doble llamada → `TypeRegistry` "already registered" `StateError`. **Fix:** guarda `if (_initialized) return`.
- **NF-21** 🟡 `outbox_queue.dart:29-42` — `enqueue` con `replace` sobre `UNIQUE(entity_type,client_id,operation)` omite `remote_id`/`synced_at`; re-encolar una op ya sincronizada borra `remote_id` y la reabre `pending` → re-push de un create que el backend ya tiene.
- **A3** 🟡 `local_database.dart:68-98` — `gasoductos`/`pks` con `CREATE TABLE IF NOT EXISTS` fuera de `_entity_schema_version`; el `_onUpgrade` global se borró. **Inocuo hoy** (app sin desplegar, migraciones desde v0) pero **medio/grave al desplegar** y aterrizar un cambio de columna — el `_onUpgrade` borrado ya mutó `gasoductos.ct TEXT → ct_id INTEGER`, prueba de que evoluciona. `hardResetGasoductos()` NO es migración (solo gasoductos, DROP destructivo). **Fix:** promover ambas a `LocalStore<T>` versionado.
- **A5** ⚪ `syncable.dart:8` — `remoteId String?` vs columna INTEGER; `int.tryParse` descarta no-numéricos en silencio. **Corrección a v1:** NO causa "re-push infinito" (el re-push lo dirige el `status` del outbox, no el store; `markSynced` del outbox es incondicional). Consecuencia real: la entidad queda `id==NULL` → un update posterior devuelve `SyncUnrecoverable 'Segmento sin id remoto'`. Latente (todos los adapters emiten ids numéricos hoy). **Fix:** columna TEXT, o loguear el descarte (no-silent-failures).
- **A6** ⚪ `gps_background_service.dart:138-141` — **Corrección a v1:** `startedAt` NO es `points.first.capturedAt` sino `_bufferStartedAt = DateTime.now()` (reloj sistema), mientras `endedAt = points.last.capturedAt` (reloj GPS) → dos relojes pueden invertir el intervalo (ordenar no basta). Además sin UTC/offset (viola el contrato ISO8601-UTC). `p.timestamp` es **no-nullable** en geolocator 14 (descartar esa preocupación). **Fix:** derivar ambos límites de los tiempos de captura con clamp `endedAt = lastCap.isAfter(startedAt) ? lastCap : startedAt`; serializar en UTC.
- **5** ⚪ `segmento_remote_adapter.dart:73` — **Corrección a v1 (bajado 🟠→⚪):** solo el conflicto en **push** está muerto. El **pull** sí pobla `sync_conflicts` + `InteractiveConflictResolver` (`app_di.dart:75`). El motor rechaza 409 con `markRejected` (sin crash ni pérdida). **Fix:** si se quiere conflicto en push, parsear el body en el adapter y devolver `SyncConflict` (NO en el mapper, que no tiene acceso al body); si no, borrar la rama muerta.
- **7** ⚪ `auth_expiration_handler.dart:42-60` — **Corrección a v1:** el duplicado no viene de "un authExpired por job" (el drain dispara una vez y `return`); viene de **operaciones secuenciales separadas** (bucle de descarga por `MasterDataKind`, o drain-luego-pull). El `finally` resetea `_handling` tras el `await`. **Fix:** `if (Get.currentRoute == AppRoutes.login) return;` al inicio + mover el snackbar dentro de la guarda de navegación.

---

## H. Limpieza, ineficiencia y código muerto

- **8** `imagen_repository_impl.dart:28-38` — `findAll()` + filtro en Dart por apertura de detalle (índice `idx_imagenes_segmento_seg` sin usar). Caller vivo: `segmento_detalle_controller.dart:114` (no hot-path). `getPendingBySegmento` (`:33-38`) es **código muerto** → borrar. Fix correcto: predicado genérico `findWhere(column,value)` en el contrato `LocalStore<T>`, no un método imagen-específico.
- **9** `sync_engine.dart:111-119` — `TaskPipeline` (5 tasks) construido+`dispose()` por job. Hoist seguro (tasks sin estado); **disponer en el `finally` `:158-160`** (hay un `return` temprano en `:131`), no tras el bucle.
- **10** ⚪ `detect_conflicts_task.dart:45` — N+1; `EnqueueConflictsTask` re-consulta por conflicto. Compartir el map de locales vía `PullContext`; preferir `findByClientIds(Set)` con `WHERE IN`. Típico N+C, no 2N.
- **A1** `_authHeader`/`markSynced` duplicados en 4 sitios; **la extracción de remote-id diverge semánticamente** (`mensaje` prefiere `id`, `position` prefiere `remote_id`, `imagen` cubre `is num` + claves extra) — riesgo de bug latente, no solo cosmético. Hoist a base/util. Nota: `NetworkService` ya añade HMAC por interceptor — los headers Bearer por-adapter pueden ser parcialmente redundantes.
- **A2** `imagen_repository_impl.dart:45` — `uploadPending(int)` ignora el parámetro; único caller `UploadImageUseCase` es **código muerto**. **Fix:** quitar parámetro → `uploadAllPending()`, borrar el use case. NO recomendar "drain con predicado" (el engine no tiene hook).
- **NF-22** ⚪ `app_router.dart:74` — `AuthMiddleware.redirect` siempre `null` → rutas protegidas no protegidas a nivel navegación.
- **NF-23** ⚪ `position_local_store.dart:148-165` — `findAll()` N+1 (query de puntos por batch). Usar query agrupada por `(batch_client_id, captured_at)`.
- **NF-24** ⚪ `position_local_store.dart:211` — `updated_at` corrupto → `tryParse` null → constructor fabrica `DateTime.now()`.
- **NF-25** ⚪ `imagen_remote_adapter.dart:64` — sniff MIME con `openRead().first` (no garantiza ≥4 bytes) → PNG pequeño mal-etiquetado JPEG.
- **Código muerto:** `SyncJobResult.pending => summary` (`sync_engine.dart:154`, rama inalcanzable), `InitializerController`, `UploadImageUseCase`, mixin `add_segmento_longpress_legacy.dart`.

---

## I. Flag pre-release vs desplegado

Casi inocuos **hoy** (app sin producción, migraciones desde v0) pero **bloqueantes el día que se despliegue** o el backend complete idempotencia: **A3** (migración master-data), **NF-19** (migración no atómica), **NF-21** (re-enqueue borra remote_id), **A5** (id no numérico). Marcar como "ship-blocker-later" para que no se pierdan tras el merge.

---

## J. Checklist de corrección (orden por dependencia)

```
BLOQUEAN MERGE (crash / pérdida de datos / éxito silencioso):
[ ] #3    main.dart:7          await AppDI.init() (o cablear InitializerController); quitar print
[ ] #1    sync_engine          acotar bucle drain + resetear _isDraining + guardar offline en call-site
[ ] #6    connectivity:12      return _isConnected.value; regression-check 3 guardas master-data
[ ] #2    segmento store       resolver identidad por remoteId, reusar clientId, enrutar a conflicto
[ ] #4    detalle:351-354      saveLocal incondicional; updateEstado solo si id!=null
[ ] NF-11 segmento repo:80     updateEstado debe manejar id==null
[ ] NF-P  detalle:261          no descartar foto en silencio; try/catch con feedback
[ ] NF-1  pull_coordinator:87  propagar fallo de tarea bloqueante; escribir pull_state de error
[ ] NF-2/3 upsert/enqueue      aflorar errores tragados (hacer bloqueantes o recolectar+reportar)
[ ] NF-10 segmento store       incluir synced_at en _entityToRow (dejar de borrarlo al editar)
[ ] NF-12 gasoductos/pks       dejar de tragar excepciones en _runOnce
[ ] NF-7/8 gps service         escribir-luego-limpiar buffer; await stop() en onClose
[ ] NF-16 mensaje repo         fallback offline en todos los errores

FOLLOW-UP (corrección, pre-despliegue):
[ ] NF-4  detect_conflicts     incluir 'syncing' en _pendingClientIds
[ ] NF-5/6 pull state/dispatch  estado error/partial; no señalar completado limpio en fallo
[ ] NF-9  gps                  abortar si operadorId inválido
[ ] NF-13/14/15 sync controller cancel a reload(); no "success" en cache; await _initRows
[ ] NF-17/18 mensaje repo      empty=success; clave de dedup fiable
[ ] NF-19 offline_database     envolver migrateEntity en transacción
[ ] NF-20 app_di              guarda de idempotencia
[ ] NF-21 outbox enqueue      preservar remote_id/synced_at al re-encolar
[ ] A3    master data         promover gasoductos/pks a LocalStore versionado
[ ] A4    image FK            migrar segmentoId a clientId
[ ] A5    remoteId codec      columna TEXT o loguear descarte
[ ] A6    gps timestamps      clamp interval + serializar UTC
[ ] #5    segmento adapter    SyncConflict en 409 (o borrar rama muerta)
[ ] #7    auth handler        guarda por ruta + snackbar dentro de la guarda

LIMPIEZA:
[ ] #8/#9/#10, A1 hoist, A2 use case muerto, NF-22..NF-25, SyncJobResult.pending, código muerto
```

---

## K. Cambios respecto a v1 (transparencia de la verificación)

- **Confirmados sin cambios:** #1, #2, #3, #4, #8, #9, #10, A1, A3.
- **Severidad corregida:** #5 🟠→⚪ (solo push muerto, pull vivo); #6 se mantiene 🟠 pero el alcance pasa de 1 a 4 guardas (refuta "ningún consumidor lo lee"); #7 se mantiene ⚪ pero se corrige el mecanismo del duplicado.
- **Mecanismo/localización corregidos:** A4 (no causa FK 0/NULL hoy — es no-op silencioso); A5 (no causa re-push infinito — causa `id==NULL` que bloquea updates); A6 (`startedAt` es reloj de sistema, no `points.first`; `timestamp` no es nullable); #2 (causa raíz en el store, no en el fetcher); #5 (fix va en el adapter, no en el mapper).
- **25 hallazgos nuevos (NF-1..NF-25 + NF-P):** el más importante es el **clúster de éxito silencioso en pull/master-data** (NF-1..NF-6, NF-12, NF-14) que v1 no cubrió, más pérdida de datos GPS (NF-7/8/9), corrupción de `synced_at` (NF-10), `updateEstado` local-only (NF-11), violaciones offline-first de mensajes (NF-16/17/18) y robustez de infra (NF-19/20/21).

---

*Generado con revisión multi-agente: 7 ángulos de búsqueda (v1) + 16 verificadores adversarios + 6 barridos de recall (v2). 30 agentes, ~2,4M tokens. Todas las líneas verificadas contra el working tree de `REDESIGN-PATRON-OUTBOX`.*
