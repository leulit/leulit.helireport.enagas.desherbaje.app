<!-- Generado por revisión multi-agente (13 agentes). Anclado a file:line del working tree de REDESIGN-PATRON-OUTBOX el 2026-06-16. Acompaña a CODE_REVIEW_REDESIGN_PATRON_OUTBOX.md. v2: D-2/D-4 anuladas y §0 (validaciones pendientes) añadida tras feedback. -->

# Plan de implementación — Corrección de hallazgos de revisión (motor offline-first Enagas Desherbaje)

> Documento de implementación definitivo. Cada workstream está anclado a `file:line` verificado contra el código real (commit en `REDESIGN-PATRON-OUTBOX`). Las correcciones del review adversarial están integradas, no apéndice. Este es el documento desde el que el equipo implementa.

---

## 0. Gobernanza y validaciones pendientes  `[BLOQUEANTE — leer primero]`

> **Regla:** este plan corrige bugs. **Ninguna decisión que modifique funcionalidad, UX o comportamiento observable se implementa sin validación explícita del responsable de producto.** Lo de abajo queda PENDIENTE DE VALIDACIÓN antes de su PR. Las correcciones internas (cuelgue, pérdida de datos, race, código muerto) no cambian lo observable y no requieren sign-off de UX.

### Correcciones ya aplicadas (feedback recibido)
- **D-2 ANULADA:** NO se añade ningún botón nuevo. Los botones **"Enviar"** (por segmento) y **"Enviar todos"** (`forzar_envio_page.dart:165/366/561`) y el aviso **"Súbelos antes de descargar"** (`sincronizacion_controller:204`) YA existen y son correctos. WS1.5 se limita a **cablear los stubs** `enviarCloud`/`enviarAllCloud` (hoy vacíos, `forzar_envio_controller.dart:115-123`) — restaura el botón existente, sin tocar UX.
- **D-4 ANULADA:** no hay edición de metadatos de imagen → el reset de `needs_sync` no aplica. NF-10 se reduce a **segmento**; imagen/mensaje son push-only/append-only.

### C — Cambios de funcionalidad/UX que introduciría el plan (REQUIEREN tu decisión)
| Item | WS | Qué cambiaría | Alternativa mínima (sin tocar UX) |
|---|---|---|---|
| Pantalla **Splash** de arranque | WS0 / #3 | Pantalla nueva con spinner + "Reintentar" mientras carga (hasta 15s) | `await AppDI.init()` directo en `main` — arranca como hoy, sin pantalla nueva (posible blanco hasta 15s en arranque lento) |
| "última descarga" solo cuenta fetch de red + hint **"desde caché"** | WS5 / NF-14 | Cambia el significado del timestamp y añade indicador en la fila | Dejar el timestamp como está (marca cualquier intento), sin hint |
| **Abortar tracking GPS** si no hay operador en sesión | WS6 / NF-9 | Hoy atribuye el lote a operador 0; pasaría a no arrancar + avisar | Mantener el comportamiento actual |

### B — Bugs cuya corrección cambia comportamiento observable (confírmame que es lo deseado)
| Item | WS | Comportamiento tras el fix |
|---|---|---|
| `isConnected` real | WS0 / #6 | Offline, "descargar"/master-data se **bloquean con aviso** (hoy lo intentan igual). Reactiva 4 guardas ya escritas en el código |
| `AuthMiddleware` redirige | WS8 / NF-22 | Rutas protegidas **redirigen a /login** sin sesión (hoy es no-op) |
| Pull sin éxito silencioso | WS4 | La sync page muestra fila **error/incompleta** cuando la descarga falla (hoy se pone verde) |
| Master-data sin tragar error | WS5 / NF-12 | Descarga fallida de trazas/PKs → fila **error** (hoy verde) |
| **Cancelar** efectivo | WS5 / NF-13 | "Cancelar" detiene también la descarga de trazas/PKs (hoy no las corta) |
| Botón descarga deshabilitado al iniciar | WS5 / NF-15 | Deshabilitado hasta cargar filas (hoy puede lanzar `StateError`) |
| Lectura de mensajes offline | WS7 / NF-16/17 | Offline sirve **caché / lista vacía** en vez de error |
| Timestamps GPS en **UTC** | WS6 / A6 | Se serializan en UTC con sufijo Z (cambio de dato enviado al backend) |

> Resuelve estos puntos (y las demás decisiones de §8) antes de que se abra ningún PR. El resto del plan (cuelgue del motor, pérdida de datos en pull/GPS, races, migraciones, limpieza) son correcciones internas que no cambian lo que ve el operario.

---

## 1. Objetivo y alcance

Corregir los hallazgos del informe de revisión del motor offline-first (push/pull, master-data, GPS, mensajes, arranque, infraestructura) **sin romper el contrato offline-first** y **sin introducir éxitos silenciosos**. El alcance es 100% cliente: ningún fix requiere cambios de backend para mergear (todos llevan puente cliente interino). Los items de backend se listan en §7 como deuda que convierte puentes en soluciones durables.

**Referencia al review:** el plan original (8 workstreams WS0–WS9 + secuenciación) y la revisión adversarial (G1–G12). Las cinco resoluciones de conflicto de spec y las cuatro correcciones P0/P1 del review adversarial están incorporadas en los workstreams correspondientes y marcadas con `[REVIEW]`.

**Hallazgo de mayor prioridad (G1) integrado:** **no existe camino de subida (push) funcional en la UI**. `SyncEngine.drain()` solo es alcanzable vía `imagen_repository_impl.uploadPending` (línea 46), cuyo único llamador es el `UploadImageUseCase` muerto. `forzar_envio.enviarCloud/enviarAllCloud` son stubs `TODO` vacíos (líneas 115-123) cableados a botones de UI que no hacen nada. **Un app offline-first que encola escrituras pero nunca las envía es un defecto funcional mayor que cualquier hallazgo individual.** Por eso se añade **WS1.5 — Cableado de push** como bloqueante real, y WS1 (bucle de drain) deja de ser "merge-blocker spine": no bloquea nada en runtime hasta que exista push.

### Fuera de alcance (declarado)
- **A4** (FK de imagen por `clientId` en vez de `id` remoto): refactor independiente, prerequisito de la visualización de fotos en segmentos local-only. Solo se deja puente interino en WS3 (NF-P).
- **Migración de columna `id` de INTEGER a TEXT** (A5 completo): ship-blocker-later documentado.
- Reescritura de `GasoductosService`/`PksService` al motor cuando exista REST único (doc backend §12.2).
- Extracción de `lib/core/sync/` a paquete `leulit_offline_sync`.

---

## 2. Principios de implementación (no negociables)

1. **Offline-first intacto.** La UI siempre lee de SQLite local. La red nunca está en el camino crítico del UX. Ningún fix puede hacer que un fallo de red borre o bloquee datos locales.
2. **Sin éxitos silenciosos.** Todo `catch` loguea o propaga. Todo desenlace de operación (push/pull/master-data/GPS) es representable y observable. El estado verde solo se muestra tras éxito real.
3. **Sin pérdida de datos.** Sesgo conservador: ante la duda, encaminar a conflicto/parcial, nunca sobrescribir o descartar. Escribir-luego-limpiar, no limpiar-luego-escribir.
4. **Un test por fix.** Cada hallazgo corregido lleva al menos un test que falla antes y pasa después (regresión). Infra de DB: `sqflite_common_ffi` in-memory (patrón de `test/core/sync/outbox/outbox_queue_test.dart`). Controllers/repos: `mocktail`.
5. **PRs pequeños, merge-blockers primero.** Un workstream grande se parte en PRs por seam natural. La espina serial se mergea antes de abanicar.
6. **Generalizar sobre parchear.** Toda decisión arquitectónica debe pasar el test de extensibilidad: añadir una entidad nueva debe seguir siendo mecánico. Se prefiere un cambio de contrato/infra compartida a un caso especial por entidad — salvo que un único método "general" introduzca un parámetro de discriminación que disfrace un caso especial (entonces gana KISS).
7. **`[REGLA DURA]` Delegación multi-fichero.** Cualquier PR/fix que toque **3+ ficheros** se ejecuta vía sub-agente implementador (Agent tool), no edición inline. Todos los workstreams salvo WS7 (1 fichero) y partes de WS0 superan ese umbral → **todos van por sub-agente**, con sets de ficheros disjuntos cuando se paralelizan.

---

## 3. Resumen de fases

| Fase | Workstreams | Esfuerzo | ¿Bloquea merge? | ¿Paralelizable dentro de fase? |
|---|---|---|---|---|
| **A — Fundación / merge-blockers** | WS0 (arranque + connectivity + AppDI init único), WS8 (contrato `migrate`→`DatabaseExecutor`, atomicidad, outbox UPSERT, AuthMiddleware) | S + M | **SÍ** | No (A1→A2 serial: ambos tocan `app_di.dart`/`app_router.dart`) |
| **B — Push + motor** | **WS1.5 (cablear push) `[REVIEW G1]`**, WS1 (bucle de drain acotado) | S + M | **WS1.5 SÍ** / WS1 no | No (WS1 estabiliza el motor que WS1.5 invoca; WS1 primero) |
| **C — Pipeline de pull** | WS2 (identidad/conflicto), WS4 (desenlace tipado) | M + M | **WS2 SÍ** (base de WS4) | No (C1→C2 serial: pipeline compartido) |
| **D — Call-sites y dominio** | WS3 (detalle local-only), WS5 (master-data + sync controller), WS6 (GPS) | M + M + M | No | **SÍ** (3 lanes disjuntas) |
| **E — Read-path y limpieza** | WS7 (mensajes), WS9 (limpieza/dedup) | S + M | No | WS7 parallel-safe desde fase A; WS9 estrictamente último |

**Espina serial de merge-blockers:** PR-1 → PR-2 → PR-4 (WS1) → PR-4.5 (WS1.5) → PR-5 (WS2). Tras PR-5, la base de pull/motor/contrato es estable y PR-6/7/8/9/10 abanican. PR-11 (WS9) cierra.

---

## 4. Matriz de colisión de ficheros

Solo ficheros tocados por ≥2 workstreams (los que fuerzan serialización o merge cuidadoso). Verificado contra source.

| Fichero | WS0 | WS1 | WS1.5 | WS2 | WS3 | WS4 | WS5 | WS6 | WS8 | WS9 | Veredicto |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `lib/core/sync/contracts/local_store.dart` | | | | ✎ `findByRemoteId(String)` | ✎ mixin upsert | | | | ✎ `migrate(Database→DatabaseExecutor)` | ✎ `findWhere` | **HOT 4-way.** WS8 firma primero, luego WS2/WS3/WS9 añaden |
| `lib/core/app_di.dart` | ✎ splash + init único | | | | | | △ (A3 shim) | | ✎ SessionState seed | △ (A3 shim) | **WS0 dueño de `init`.** WS8 solo añade SessionState seed dentro del `_init()` de WS0 |
| `lib/core/sync/engine/sync_engine.dart` | | ✎ bucle acotado, hoist, drop `.pending` | | | | | | | | △ (WS9 5d mooted) | **WS1 gana.** WS9 dropea 5d |
| `lib/core/sync/engine/sync_job_context.dart` | | ✎ `result` nullable, quita `.pending` | | | | | | | | △ | **WS1 supersede WS9** |
| `lib/data/sync/segmento_local_store.dart` | | | | ✎ upsert (drop replace), `findByRemoteId`, markSynced log | △ (synced_at req → WS2) | | | | ✎ migrate sig | ✎ findWhere, parseRemoteId | **HOT.** Upsert reconciliado, dueño WS2 |
| `lib/data/sync/mensaje_local_store.dart` | | | | ✎ `findByRemoteId` | ✎ upsert-preserve synced_at | | | | ✎ migrate sig | ✎ findWhere wrapper, parseRemoteId | **HOT.** WS3 dueño upsert |
| `lib/data/sync/imagen_local_store.dart` | | | | ✎ `findByRemoteId` | ✎ upsert-preserve synced_at | | | | ✎ migrate sig | ✎ findWhere, parseRemoteId | **HOT.** WS3 dueño upsert |
| `lib/data/sync/position_local_store.dart` | | | | ✎ `findByRemoteId` | △ (NF-10 opt) | | ✎ NF-23 findAll, NF-24 | ✎ migrate sig | ✎ findWhere, parseRemoteId | **HOT.** WS6 findAll, WS9 findWhere |
| `lib/data/repository/segmento_repository_impl.dart` | | | | ✎ `findByRemoteId(id.toString())` :45,:80 | ✎ updateEstado DartDoc :80, saveLocal | | | | | | **WS2 & WS3 editan :80.** WS2 primero |
| `lib/data/repository/imagen_repository_impl.dart` | | ✎ offline-guard `uploadPending` | △ | | | | | | | ✎ rename→`uploadAllPending`, del `getPendingBySegmento`, `findWhere` | **HOT.** WS1 guard → WS9 rename |
| `lib/core/sync/outbox/outbox_queue.dart` | | △ | △ | ✎ `syncingJobs` | | | | | ✎ enqueue UPSERT | | Métodos disjuntos, mismo fichero |
| `lib/core/sync/pull/pull_context.dart` | | | | ✎ `ResolvedPullItem` (listas) | | ✎ partialErrors/outcome/errorMessage | | | | | **WS2 & WS4.** WS2 primero |
| `lib/core/sync/pull/tasks/upsert_non_conflicting_task.dart` | | | | ✎ usa clientId resuelto | | ✎ try/catch por-item | | | | | **WS2 & WS4.** WS2 primero |
| `lib/core/sync/pull/tasks/enqueue_conflicts_task.dart` | | | | ✎ consume ResolvedPullItem | | ✎ try/catch por-item | | | | | **WS2 & WS4.** WS2 primero |
| `lib/presentation/sincronizacion/sincronizacion_controller.dart` | | | △ | | | ✎ branch degradado :211-242 | ✎ master-data :184/195, `_initRows`, `_rowFor` | | △ (SessionState set(false) :131) | | **4-way, rangos disjuntos.** Serializar merges |
| `lib/presentation/forzar_envio/forzar_envio_controller.dart` | | | ✎ implementar stubs | | | | | | | | **WS1.5 dueño** |
| `lib/core/app_router.dart` | ✎ ruta `/splash` | | | | | | | | ✎ `AuthMiddleware.redirect` | | Bloques disjuntos |
| `lib/initializer_controller.dart` (DELETE) | ✎ DELETE | | | | | | | | | △ (defiere a WS0) | **WS0 borra** |

**Restricciones de serialización (merge-blockers):**
1. `local_store.dart`: aterrizar firma de WS8, luego añadir WS2/WS9/WS3.
2. `app_di.dart` init: WS0 dueño de la implementación única (`_initFuture` de WS8). WS8 solo añade el seed de SessionState dentro de ese cuerpo.
3. Los 4 `*_local_store.dart`: `upsert()` reescrito por WS2 (segmento), WS3 (mensaje/imagen) y WS6 (position findAll). WS2 dueño del upsert de segmento (requisito más rico).
4. Trío de pull (`pull_context`, `upsert_non_conflicting_task`, `enqueue_conflicts_task`): **WS2 primero** (introduce `ResolvedPullItem`), WS4 superpone manejo de error por-item.

---

## 5. Workstreams

### WS0 — Arranque y conectividad (quick wins)
**Cubre:** #3, #6, NF-20, DC-InitializerController, DC-print/lint.

**Problema (verificado):**
- **#3** `main.dart:5-9`: `main()` no es async; `AppDI.init()` es fire-and-forget (`.then((_) => print(...))`) y `runApp` arranca de inmediato con `initialRoute: AppRoutes.login` (`main_app.dart:17`). `LoginPageController:8` tiene `final _repo = AuthRepositoryImpl();` → `auth_repository_impl.dart:9 final _provider = AuthDataProvider();` → `auth_data_provider.dart:8 Get.find<NetworkService>()`. `AppDI.init` registra `NetworkService` solo tras un `putAsync` + apertura SQLite (timeout 15s, `app_di.dart:31-51`). Si el primer frame construye el binding de login antes de que init llegue a línea 36 → `'NetworkService not found'` → crash de arranque. Casi seguro en primer lanzamiento (creación de DB) / dispositivos lentos.
- **#6** `connectivity_service.dart:12`: `bool get isConnected => true;//_isConnected.value;`. Mata 5 guards imperativos (sincronizacion :85/:108, gasoductos :102, pks :85, json_loader :85).
- **NF-20** `app_di.dart:29`: `init()` no es idempotente; segunda llamada → `TypeRegistry.register` lanza `StateError('already registered')` (`type_registry.dart:39`).
- **Lint/DC:** `print(` en `main.dart:8` e `initializer_controller.dart:17`. `InitializerController` muerto (cero llamadores).

**Enfoque:**
1. **AppDI init único `[REVIEW: resuelve conflicto WS0/WS8]`** — adoptar el **completer de WS8** (cubre doble llamada secuencial Y concurrente; estrictamente más fuerte que el bool de WS0):
   ```dart
   class AppDI {
     static Future<void>? _initFuture;
     static Future<void> init() => _initFuture ??= _init();
     static Future<void> _init() async { /* cuerpo actual de líneas 30-62 */ }
     @visibleForTesting static void resetForTest() => _initFuture = null;
   }
   ```
   Renombrar el cuerpo de `init()` a `_init()`. **WS8 NO re-implementa NF-20.** Si `_init()` lanza, el `_initFuture` queda completado-con-error; `resetForTest()` y el reintento del splash crean uno nuevo (el splash llama `AppDI.init()` que re-evalúa `??=` solo si se hizo `resetForTest`; **por eso el splash retry debe llamar `AppDI.resetForTest()` antes de re-`init()`** — documentar).
2. **Splash gate (sustituye InitializerController)** — DELETE `lib/initializer_controller.dart`. CREATE `lib/presentation/splash/`:
   - `splash_controller.dart`: `isLoading.obs`, `error.obs<String?>`; `onInit → _bootstrap()`; `_bootstrap` hace `AppDI.resetForTest()`-equivalente solo en retry, `await AppDI.init()`, `Get.offAllNamed(login)` en éxito, captura → `error.value=...`, `AppLog.e(...)`, `isLoading=false`. `retry()` → `_bootstrap()`.
   - `splash_page.dart`: `StatelessWidget + GetView<SplashController>`, `Obx` estrecho: spinner mientras `isLoading`, card de error + botón "Reintentar" si `error != null`.
   - `splash_binding.dart`: `Get.put<SplashController>(SplashController())` (eager, debe correr `onInit` como ruta de entrada).
3. **Routing** — `AppRoutes.splash = '/splash'`; `GetPage(splash, SplashPage, SplashBinding())` sin `AuthMiddleware`. `main_app.dart:17`: `initialRoute → AppRoutes.splash`.
4. **main.dart** — `void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const MainApp()); }`. Quitar el `print`, el `.then`, el import de `app_di.dart`.
5. **Logger `[REVIEW G6: WS7 depende de esto]`** — introducir `lib/core/app_log.dart`, facade estático sobre `logger: ^2.7.0` (`AppLog.e/i/w`). **No-silent-failures exige loguear con stack; `debugPrint` se strippea en release.** Es el primer logger del proyecto y desbloquea el logging requerido por WS5/WS6/WS7. **Decisión: introducir AppLog ahora** (ver §8 D-1).
6. **#6** — `connectivity_service.dart:12 → bool get isConnected => _isConnected.value;`. `_updateStatus` ya mantiene el observable; re-arma los 5 guards. La defensa de simulador (`_hasActualInternet()` DNS, :58-66) sigue intacta.

**Ficheros tocados:** `main.dart`, `main_app.dart`, `app_di.dart`, `app_router.dart`, `connectivity_service.dart`, `initializer_controller.dart` (DELETE), `splash/splash_controller.dart` (NEW), `splash/splash_page.dart` (NEW), `splash/splash_binding.dart` (NEW), `core/app_log.dart` (NEW).

**Tests nuevos:**
- `test/core/app_di_idempotency_test.dart`: con ffi + `Get.reset()` — (a) primera `init()` registra segmento/imagen/mensaje/position en TypeRegistry; (b) segunda `init()` (secuencial Y `Future.wait` paralelo) NO lanza y comparte `_initFuture`; (c) `resetForTest()` permite re-init.
- `test/core/services/connectivity_service_test.dart`: el getter refleja `_isConnected.value` tras drivear `_updateStatus` vía `onConnectivityChanged` stubeado.
- `test/presentation/splash/splash_controller_test.dart`: éxito → `Get.offAllNamed(login)`; fallo de init → `error != null`, `isLoading == false`, sin excepción escapada; `retry()` re-invoca bootstrap.
- `test/presentation/sincronizacion/sincronizacion_controller_offline_test.dart`: con `ConnectivityService` doble `isConnected == false`, `descargar*` ponen `lastError == 'No hay conexión a internet.'` y no descargan.

**Criterios de aceptación:**
- Cold start en dispositivo lento / primer lanzamiento nunca lanza `'NetworkService not found'`.
- `flutter analyze --fatal-infos` sin `avoid_print`; `grep -rn 'print(' lib/` solo devuelve `debugPrint`/comentarios.
- `grep -rn 'InitializerController' lib/` → 0.
- `connectivity_service.dart:12` lee `=> _isConnected.value;`.
- `AppDI.init()` ×2 no lanza; fallo de init muestra error + "Reintentar" (sin pantalla blanca).

**Riesgos de regresión:** cambio `initialRoute` login→splash — verificar que `Get.offAllNamed(login)` de reset (sincronizacion `volver()`, auth_expiration logout) siga correcto. Re-armar `isConnected` activa los 5 guards: los 4 de master-data son benignos (cache fallback/no-op); sincronizacion descargar/descargarTodo ahora cortocircuitan offline (fix intencionado, marcar para QA). `splash_binding` usa `Get.put` eager — verificar que GetX dispone el binding al `offAll(login)` (no `permanent`).

**Dependencia de backend:** ninguna.

**Decisiones abiertas:** O2 (logger) resuelta → **AppLog ahora** (§8 D-1). Splash retry debe llamar `resetForTest()` antes de re-init dado el completer — documentado arriba.

---

### WS8 — Robustez de infraestructura
**Cubre:** NF-19, NF-21, NF-22 (NF-20 lo entrega WS0).

**Enfoque:**

**NF-19 (ship-blocker-later): `migrateEntity` atómico.** `offline_database.dart:46-47` ejecuta `store.migrate()` y `_writeVersion()` sin transacción. Restricción: `LocalStore.migrate(Database db, …)` (`local_store.dart:25`) recibe `Database`; sqflite prohíbe transacción anidada y `Transaction` no implementa `Database` (sí `DatabaseExecutor`). **Verificado:** las 4 stores usan solo `db.execute(...)` en `migrate` (disponible en `DatabaseExecutor`); cambio mecánico. **`[REVIEW]` Confirmado: `position_local_store.upsert:69` usa `executor.transaction(...)` en RUNTIME, no en `migrate` — envolver `migrateEntity` en transacción es seguro.**
1. `local_store.dart:25` → `Future<void> migrate(DatabaseExecutor db, int from, int to);` (y doc-comment).
2. 4 stores: cambiar firma `Database`→`DatabaseExecutor` (sin cambios de cuerpo).
3. `offline_database.dart:33-48` — envolver lectura+migrate+escritura en una sola `db.transaction`; lanzar `StateError` si `current > target` (downgrade no soportado).
4. `_readVersion`/`_writeVersion` (`:125,:136`) — primer parámetro `Database`→`DatabaseExecutor`.

**NF-21 (ship-blocker-later): enqueue no debe pisar `remote_id`/`synced_at`.** `outbox_queue.dart:29-42` usa `ConflictAlgorithm.replace` sobre `UNIQUE(entity_type,client_id,operation)` → BORRA la fila previa (`remote_id`/`synced_at` → NULL) y la deja `pending`. Re-encolar una op ya `synced` reabre un create que el backend ya tiene. Reemplazar por UPSERT explícito que resetea solo campos de intento y preserva `remote_id`/`synced_at`/`created_at`:
```dart
await executor.rawInsert('''
  INSERT INTO $_table (entity_type, client_id, operation, status, attempts, last_error, status_code, created_at)
  VALUES (?, ?, ?, ?, 0, NULL, NULL, ?)
  ON CONFLICT(entity_type, client_id, operation) DO UPDATE SET
    status='${SyncStatus.pending.wireName}', attempts=0, last_error=NULL, status_code=NULL
''', [entityType, clientId, operation.wireName, SyncStatus.pending.wireName, now]);
final rows = await executor.query(_table, columns: ['id'],
  where: 'entity_type=? AND client_id=? AND operation=?',
  whereArgs: [entityType, clientId, operation.wireName], limit: 1);
final id = rows.first['id']! as int;
```
`[REVIEW G10]` FIFO: el plan original decía "FIFO sin cambios". **Corrección:** preservar `created_at` mantiene FIFO por `created_at`, **pero `id` ya no se renueva en re-enqueue** (antes `replace` hacía delete+insert → nuevo autoincrement). `nextPending` ordena por `created_at ASC, id ASC` — benigno, pero ningún test debe asertar orden por `id`. ON CONFLICT requiere SQLite ≥ 3.24 (2018); minSdk 34 y `sqflite_common_ffi` lo soportan.

**NF-22: AuthMiddleware redirige sin sesión.** `app_router.dart:74` siempre devuelve `null`. `GetMiddleware.redirect` es SÍNCRONO; el token vive en `flutter_secure_storage` (async). Introducir flag de sesión en memoria:
1. `lib/core/services/session_state.dart`: `GetxService` con `bool hasSession` + `set(bool)`.
2. `app_di.dart` — `Get.put<SessionState>(SessionState(), permanent: true)` y sembrar `set(await AuthRepositoryImpl().isAuthenticated())`. `[REVIEW G8]` **Este seed va DENTRO del `_init()` que WS0 posee** (no una segunda definición de init), envuelto en try/catch → `false` ante fallo de secure_storage (no bloquear arranque que ya tiene timeout de 15s).
3. `login_page_controller.dart` tras login OK: `set(true)`.
4. `auth_expiration_handler.dart:45` tras logout: `set(false)`.
5. `sincronizacion_controller.dart:131` (logout manual): `set(false)`.
6. `app_router.dart:72-79`:
   ```dart
   RouteSettings? redirect(String? route) {
     if (route == AppRoutes.login) return null;
     final ok = Get.isRegistered<SessionState>() && Get.find<SessionState>().hasSession;
     return ok ? null : const RouteSettings(name: AppRoutes.login);
   }
   ```
   `Get.isRegistered` evita crash si el router corre antes de AppDI. NF-22 es defensa-en-profundidad (⚪) pero cierra la promesa de "ruta protegida".

**Ficheros tocados:** `offline_database.dart`, `local_store.dart`, 4 stores (firma migrate), `outbox_queue.dart`, `app_di.dart`, `app_router.dart`, `session_state.dart` (NEW), `login_page_controller.dart`, `auth_expiration_handler.dart`, `sincronizacion_controller.dart`.

**Tests nuevos:**
- `test/core/sync/database/offline_database_migrate_test.dart` (ffi): (a) primera apertura crea tabla + version=1; (b) idempotencia: segunda migrate = no-op (contador en FakeStore); (c) **atomicidad: FakeStore cuyo migrate hace un CREATE válido y luego lanza → version sigue 0 Y la tabla no existe (rollback)**; (d) downgrade lanza StateError.
- `test/core/sync/outbox/outbox_queue_test.dart` (AMPLIAR grupo enqueue): (a) re-enqueue de op ya synced preserva `remote_id`/`synced_at`, status→pending, attempts→0; (b) preserva `created_at`; (c) ajustar test idempotente existente.
- `test/core/app_router_auth_middleware_test.dart`: (a) sin sesión → redirect a `/login`; (b) con sesión → `null`; (c) `/login` siempre `null` (no loop); (d) SessionState no registrado → `/login` sin lanzar.

**Criterios de aceptación:** ver tests. Doc-comment de `migrate`/`migrateEntity` ya no menciona `Database`. CLAUDE.md documenta la nueva firma `migrate(DatabaseExecutor)`.

**Riesgos de regresión:** cambio de firma `migrate` rompe compilación de cualquier store fuera de las 4 (verificado: solo 4). enqueue UPSERT: callers vivos `offline_repository.dart:39` (delete) y `:56` (`_persistAndEnqueue`), ambos dentro de `db.transaction` pasando `txn` — `rawInsert`/`query` funcionan en `Transaction`. AuthMiddleware activo puede afectar tests de widgets que naveguen a rutas protegidas sin sembrar SessionState (fallback a `/login`).

**Dependencia de backend:** ninguna. NF-21 cobra valor pleno cuando el backend sea idempotente por `client_id` (BE-3).

**Decisiones abiertas:** NF-21 preservar vs refrescar `created_at` → **preservar** (FIFO justo). SessionState ahora vs esperar AuthService → **SessionState ahora** (embrión del futuro AuthService).

---

### WS1.5 — Cableado de push `[REVIEW G1 — NUEVO, MERGE-BLOCKER]`
**Cubre:** G1 (defecto funcional: no hay camino de subida).

**Problema (verificado):** `forzar_envio_controller.dart:115-123` `enviarCloud`/`enviarAllCloud` son cuerpos `TODO` vacíos, cableados a `forzar_envio_page.dart:165` y `:366`. El único `drain()` vivo es `imagen_repository_impl.uploadPending:46`, cuyo único llamador es el `UploadImageUseCase` muerto. **El operador puede encolar cambios de segmento/imagen/mensaje indefinidamente sin enviarlos jamás.**

**Enfoque:** implementar el push real en `ForzarEnvioController`:
- `enviarCloud(SegmentoEntity segmento)`: drenar el outbox de las entidades relevantes (segmento + sus imágenes/mensajes). Como `SyncEngine.drain(entityType:)` drena por tipo, invocar `drain('segmento')`, `drain('imagen')`, `drain('mensaje')` en secuencia (o un `drainAll()` nuevo en el engine que itere los `entityType` registrados — ver decisión abierta). **Guard offline en el call-site** (`ConnectivityService.isConnected`, ya re-armado por WS0): si no hay red, mostrar `lastError` y no drenar.
- `enviarAllCloud()`: drenar todas las entidades pendientes (todos los `entityType` con adapter registrado).
- Inyectar `SyncEngine` + `ConnectivityService` en el controller (via binding).
- Surface del `DrainSummary`: tras drenar, mostrar resumen (subidos / reintentables / rechazados / conflictos) y refrescar la lista. `authExpired` → ya manejado por `AuthExpirationHandler`.

**Dependencia de orden:** WS1 (bucle de drain acotado) debe aterrizar ANTES — WS1.5 invoca un `drain()` que sin WS1 cuelga en bucle infinito ante un solo job reintentable offline. La espina es **WS1 → WS1.5**.

**Ficheros tocados:** `forzar_envio_controller.dart`, `forzar_envio_binding.dart` (inyección de `SyncEngine`/`ConnectivityService`), posible `sync_engine.dart` (si se añade `drainAll()`). **NO se añade UI nueva** — los botones "Enviar" (por segmento, `forzar_envio_page.dart:366/561`) y "Enviar todos" (`:165`) YA existen; solo se cablean los stubs.

**Tests nuevos:**
- `test/presentation/forzar_envio/forzar_envio_controller_test.dart` (mocktail sobre `SyncEngine`/`ConnectivityService`): (a) `enviarCloud` con red → invoca `drain` para segmento/imagen/mensaje; (b) sin red → no invoca drain, pone `lastError`; (c) `enviarAllCloud` drena todos los tipos; (d) `DrainSummary` con rechazados/conflictos se surface en la UI (estado observable).

**Criterios de aceptación:**
- `grep -rn 'TODO: implementar envío' lib/presentation/forzar_envio/` → 0.
- Encolar un cambio de segmento (WS3) + pulsar "Enviar" con red drena el outbox y el job pasa a `synced` (verificable: `countPending` baja).
- Sin red, "Enviar" no cuelga ni intenta (cortocircuito por guard).
- El operador ve un resumen del envío (no un botón que no hace nada).

**Riesgos de regresión:** drenar por-tipo secuencial puede disparar varios `AuthExpiredException` si el primer tipo aborta auth — el segundo drain debe respetar el abort (verificar que tras `authExpired` no se sigue drenando otros tipos; cortar el bucle de tipos al primer `authExpired`).

**Dependencia de backend:** ninguna para el cableado. La idempotencia por `client_id` (BE-3) hace seguro el reintento.

**Decisiones abiertas:**
- **¿`drainAll()` en el engine o bucle de tipos en el controller?** RECOMENDACIÓN: bucle de tipos en el controller (el engine sigue agnóstico de qué entidades existen; el controller conoce el dominio). Si se prefiere centralizar, `drainAll()` itera `TypeRegistry` — pero entonces el engine debe parar al primer `authExpired`.
- **Botón en sync page: NO se añade** `[D-2 ANULADA por feedback]`. Los botones "Enviar"/"Enviar todos" en forzar-envío y el aviso "Súbelos antes de descargar" ya existen y son correctos; WS1.5 solo cablea los stubs. Ver §0.

---

### WS1 — Motor drain: bucle acotado
**Cubre:** #1, #9 (hoist/dispose pipeline), DC `SyncJobResult.pending`, offline-guard call-site.

> `[REVIEW G1]` **Re-rango:** WS1 NO es la espina de merge-blockers original. El bug es real pero hoy untriggerable (no hay push). Tras añadir WS1.5, WS1 pasa a ser **prerequisito de WS1.5** (WS1.5 invoca `drain()`). Sigue siendo merge-blocker, pero por WS1.5, no por sí mismo.

**Causa raíz (#1, verificada):** `sync_engine.dart:83` itera `while(true)` re-consultando `_outbox.nextPending(status='pending')` (orderBy `created_at ASC, id ASC`). Un job reintentable vuelve a `pending` vía `markPendingAgain` SIN tocar `created_at` → la siguiente vuelta re-devuelve el mismo job. `syncOutcomeFromNetworkError` mapea offline/timeout/5xx/429 → `SyncRetryable` → bucle infinito determinista offline. Peor: `_isDraining` solo se resetea en el `finally` que nunca se alcanza → brick permanente de toda la sesión.

**Mecanismo `[Set<int> de ids procesados]`** (cero migración, cero impacto en `countPending`, generaliza para toda entidad):
1. `sync_engine.dart` `drain()` (`:78-162`):
   - Tras `_isDraining = true;`: `final processed = <int>{};`.
   - **HOIST del pipeline FUERA del bucle** (los 5 tasks son stateless, verificado #9): construir una vez antes del `while`.
   - Filtrar batch: `final fresh = batch.where((j) => !processed.contains(j.id)).toList(); if (fresh.isEmpty) break;` (sustituye `if (batch.isEmpty) break;`).
   - `for` itera `fresh`; `processed.add(job.id)` al INICIO de cada iteración.
   - Envolver el `while` en `try { … } finally { pipeline.dispose(); _isDraining = false; }` — dispose exactamente una vez incluido el return temprano por auth.
   - Eliminar la rama `SyncJobResult.pending => summary` del switch.
2. `sync_job_context.dart`: eliminar valor `pending` del enum `SyncJobResult` (`:21-27`); campo `SyncJobResult? result;` (`:16`); leer `ctx.result!` tras éxito del pipeline (InterpretOutcomeTask siempre asigna uno de los 4 reales). `[REVIEW: resuelve conflicto WS1/WS9]` **WS9 dropea su decisión 5d** (el argumento "mantener + assert" queda mooted al hacer `result` nullable).
3. `imagen_repository_impl.dart:45-46` — offline-guard:
   ```dart
   Future<DrainSummary> uploadPending(int segmentoId) async {
     if (!_connectivity.isConnected) return const DrainSummary();
     return _engine.drain(entityType: 'imagen');
   }
   ```
   Inyectar `ConnectivityService? connectivity` con `?? Get.find<ConnectivityService>()`.

> No se toca `outbox_queue.dart` ni `offline_database.dart` (Set<int> los deja intactos).

**Tests nuevos:** `test/core/sync/engine/sync_engine_test.dart` (ffi + TypeRegistry real con fake store/adapter configurable):
- TEST A (#1): adapter siempre `SyncRetryable`, 1 job → drain TERMINA (timeout/fake_async), `retryable:1`, adapter invocado exactamente 1 vez, `isDraining == false`.
- TEST B (brick): segunda `drain()` re-entra (no no-op).
- TEST C (multi-batch): 150 jobs todos `SyncSuccess`, limit 100 → `succeeded:150` sin re-procesar; **asertar transición de status a `synced`** (no solo el Set) `[REVIEW G9]`.
- TEST D (mezcla): success/retryable/unrecoverable → `succeeded:1, retryable:1, rejected:1`, cada adapter-call 1 vez.
- TEST E (auth): `AuthExpiredException` en el 2º de 3 → `authExpired==true`, job auth queda `pending`, `isDraining==false`, `SyncActions.authExpired` 1 vez.
- TEST F (sin registro / read-only): markRejected + `rejected:1`.
- TEST G (dispose): exactamente una vez por drain, incluido return por auth.
- TEST H: offline-guard en `imagen_repository_impl_test.dart` — `isConnected==false` → `verifyNever(drain)`, DrainSummary vacío.

**Criterios de aceptación:** drain con N reintentables TERMINA; `isDraining==false` tras cualquier desenlace; ningún job al pipeline >1 vez/invocación; multi-batch procesa todos; pipeline construido 1 vez, dispuesto 1 vez; `SyncJobResult.pending` no existe; switch exhaustivo; `uploadPending` no drena offline.

**Riesgos de regresión:** `imagen_repository_impl.uploadPending` ahora devuelve summary vacío offline en vez de retryables — WS1.5/ForzarEnvioController debe interpretar summary vacío como "nada que hacer". Hoist del pipeline asume tasks stateless (verificado) — documentar precondición.

**Dependencia de backend:** ninguna.

**Decisiones abiertas:** Set<int> vs estado transitorio → **Set<int>**. Sin tope de seguridad (terminación garantizada). Offline-guard en call-site (no en engine) → mantener engine agnóstico de `ConnectivityService` (objetivo paquete extraíble).

---

### WS2 — Identidad y conflicto en pull de segmentos
**Cubre:** #2, NF-4, A5, #5.

**Causa raíz #2:** el backend omite `client_id` → `SegmentoEntity.fromJson:120` (`_clientId = clientId ?? const Uuid().v4()`) acuña UUID nuevo en cada pull. `DetectConflictsTask:45` hace `findByClientId(newUuid)` → null → `safeToUpsert` → `UpsertNonConflictingTask` llama `store.upsert(remote)` (`upsert_non_conflicting_task.dart:30`) con `ConflictAlgorithm.replace` (`segmento_local_store.dart:72`). `INSERT OR REPLACE` borra la fila que colisiona en el índice parcial `idx_segmentos_remote ON segmentos(id) WHERE id IS NOT NULL` (`:59-62`). La fila local (con la edición pendiente del operador, keyed al UUID viejo) se destruye; el job del outbox queda huérfano → `StateError` en el siguiente drain (alimenta #1).

**STEP 1 — Generalizar `findByRemoteId` al contrato.** `local_store.dart` (tras `findAll()`): `Future<T?> findByRemoteId(String remoteId);`. Implementar en `SegmentoLocalStore` (adaptar el `findByRemoteId(int)` existente `:128` a `String`, parse a int interno, log de descarte si no-numérico — A5). Actualizar `segmento_repository_impl.dart:45,:80` a `id.toString()`. Implementar en imagen/mensaje/position (push-only pueden devolver null; el método debe existir por contrato).

**STEP 2 — Resolución de identidad en pull.** `detect_conflicts_task.dart` (`:39-57`): antes de `findByClientId(remote.clientId)`, si `remote.remoteId != null` probar `findByRemoteId(remote.remoteId!)`. Si hay match local por remoteId, el `clientId` local es la identidad canónica.
- **Cambiar `PullContext.safeToUpsert`/`conflicts` de `List<T>` a `List<ResolvedPullItem<T>>`** donde `ResolvedPullItem = ({T remote, String clientId, T? local})`, poblado en `DetectConflictsTask` y consumido por `UpsertNonConflictingTask`/`EnqueueConflictsTask`. Esto **también mata el N+1 de `EnqueueConflictsTask` (#10)** (el `local` ya viaja).
- Clasificación: sin match por clientId ni remoteId → `safeToUpsert` (nuevo). Con match (cualquier clave): `localIsNewer = local.updatedAt.isAfter(remote.updatedAt)`, `hasPending = pendingClientIds.contains(local.clientId)`; si `localIsNewer || hasPending` → `conflicts`, si no → `safeToUpsert` bajo `local.clientId`.

**STEP 3 — Re-bind del clientId local en el upsert.** `SegmentoEntity._clientId` es final. Producir un `T` con el clientId local vía `fromJson` (ya requerido por entidad, expuesto en `TypeRegistration`):
```dart
final rebound = ctx.registration.fromJson({...remote.toJson(), 'client_id': resolvedClientId});
```
Verificar que `fromJson` está expuesto en `TypeRegistration` (`type_registry.dart`) y round-trippea sin pérdida (`ubicacion_gis`, `imagenes`, `mensajes`).

**STEP 4 — NF-4: incluir `syncing` en el set de pendientes.** `detect_conflicts_task.dart:61-70` `_pendingClientIds` consulta `pendingJobs` + `rejectedJobs`. Añadir `outbox.syncingJobs(entityType:)` (`outbox_queue.dart`: `Future<List<SyncJob>> syncingJobs({String? entityType}) => _allWithStatus(SyncStatus.syncing, entityType: entityType);`). Un pull concurrente con drain en vuelo no debe clasificar un clientId `syncing` como `safeToUpsert`.

**STEP 5 — Eliminar `ConflictAlgorithm.replace` en `SegmentoLocalStore.upsert`.** `[REVIEW G3 — reconciliación crítica con WS3]` WS2 quiere que una colisión de remote-id en un client_id distinto **lance** (surface, no silent); WS3 quiere preservar `synced_at`. **No se obtiene ambos de un upsert ingenuo:** `insert(ignore)` traga la colisión del índice parcial que WS2 quiere surface, y el `update WHERE client_id` actualiza 0 filas → pérdida silenciosa. **Reconciliación explícita en dos pasos (verificado: `_entityToRow` omite `synced_at`, `:152`, por lo que el UPDATE lo preserva gratis):**
```dart
@override
Future<void> upsert(SegmentoEntity entity, {DatabaseExecutor? txn}) async {
  final executor = txn ?? _db;
  final changed = await executor.update(_table, _entityToRow(entity),
      where: 'client_id = ?', whereArgs: [entity.clientId]);   // preserva synced_at
  if (changed == 0) {
    // fila nueva: una colisión en idx_segmentos_remote (mismo id, distinto client_id) DEBE lanzar
    await executor.insert(_table, _entityToRow(entity),
        conflictAlgorithm: ConflictAlgorithm.abort);
  }
}
```
Tres casos cubiertos por test: (a) mismo client_id → UPDATE preserva synced_at; (b) client_id nuevo + id nuevo → INSERT; (c) client_id nuevo + id colisionante → THROW (no borra). **WS2 es dueño de este upsert de segmento; WS3 solo añade el requisito synced_at a mensaje/imagen.**

**STEP 6 — A5: codec remoteId.** `markSynced` (`:104-124`) hace `int.tryParse` y descarta silencioso no-numérico → loguear (`AppLog.w`, de WS0) y dejar `id` null. Igual en el nuevo `findByRemoteId`. **La columna `id` sigue INTEGER en este WS** (la migración a TEXT toca el índice parcial + parsing + callers int → ship-blocker-later).

**STEP 7 — #5: 409 en push.** `[REVIEW G11 — verificado: no existe rama 409→SyncConflict en el adapter]` `segmento_remote_adapter.dart` ya devuelve `SyncUnrecoverable` para cualquier `statusCode` no-éxito (`:69-71`); no hay rama 409 muerta que borrar. **Decisión: opción (b) — `[REVIEW]` no tocar `network_error.dart`/`network_service.dart`; mantener 409→`SyncUnrecoverable` con mensaje español claro.** Reintroducir `SyncConflict`-en-push solo cuando el backend garantice 409-con-body (BE-8). El #5 es esencialmente un no-op de código + nota de contrato.

**Ficheros tocados:** `local_store.dart`, 4 stores, `segmento_repository_impl.dart`, `detect_conflicts_task.dart`, `upsert_non_conflicting_task.dart`, `enqueue_conflicts_task.dart`, `pull_context.dart`, `type_registry.dart`, `outbox_queue.dart`, `segmento_remote_adapter.dart` (solo mensaje 409). **No se toca `network_error.dart`/`network_service.dart`** (#5 opción b).

**Tests nuevos:**
- `test/data/sync/segmento_local_store_test.dart` (ffi, recreando tabla + índice parcial): (a) upsert de remote con client_id distinto pero MISMO id que fila local NO borra la local; (b) upsert con client_id existente actualiza en sitio (row count 1); (c) client_id nuevo + id colisionante LANZA; (d) `findByRemoteId('42')` encuentra; (e) `findByRemoteId('not-a-number')` → null + log; (f) `markSynced` no-numérico deja `id` null + log.
- `test/core/sync/pull/detect_conflicts_task_test.dart` (mocktail): (a) match por remoteId, clientId distinto, remoto más nuevo, sin pendiente → `safeToUpsert` con clientId LOCAL; (b) local más nuevo → `conflicts`; (c) job pending → `conflicts`; (d) **job syncing → `conflicts` (NF-4)**; (e) nuevo total → `safeToUpsert`; (f) `ResolvedPullItem` lleva clientId local.
- `test/core/sync/pull/upsert_non_conflicting_task_test.dart`: upsert con clientId LOCAL resuelto; `markSynced` con ese clientId; 1 `entitySynced` por item.
- `test/core/sync/outbox/outbox_queue_test.dart` (EXTEND): `syncingJobs` filtra por status + entityType.

**Criterios de aceptación:** repro del review arreglada (pull → edit offline → pull: edición preservada en `sync_conflicts`, job válido, sin StateError); índice parcial nunca dispara REPLACE destructivo; `replace` eliminado, colisión surface; detección consulta pending+rejected+syncing; contrato declara `findByRemoteId(String)` (sin cast segmento-específico en la task); markSynced/findByRemoteId loguean descarte no-numérico; 409 → `SyncUnrecoverable` con mensaje español.

**Riesgos de regresión:** cambio de firma `findByRemoteId(int→String)` fuerza `segmento_repository_impl:45,:80` (alcanzados por SegmentosList/Detalle controllers) — coordinar con WS3 NF-11 (mismo `:80`). `PullContext` `List<T>→List<ResolvedPullItem<T>>` ripplea a las 2 tasks + posibles contadores del summary del coordinator — verificar `upserted`/`conflicts.length`. Quitar `replace` afecta el push path (`UpdateLocalStateTask:47`) y `OfflineRepository.create/update:55` — el update-then-insert debe seguir correcto para create/update normal (test b). `fromJson` round-trip — confirmar sin campo lossy (`synced_at` no está en `toJson`, no importa para la fila upserteada).

**Dependencia de backend:** **BE-1** (echo `client_id` estable en pull `segmentos/bycts` y en update). Puente interino: resolución por id numérico + reuso de client_id local (STEP 2-3). **BE-8** opcional para #5 opción (a).

**Decisiones abiertas:** #5 → **opción (b)**. Carrier de identidad → **`ResolvedPullItem`** (también arregla #10). Re-bind → **reusar `fromJson`** (cero extension points). A5 id column → **INTEGER + log** (TEXT diferido). syncingJobs → **incluir incondicionalmente** (sesgo no-pérdida).

---

### WS4 — Pipeline de pull: fin del éxito silencioso
**Cubre:** NF-1, NF-2, NF-3, NF-5, NF-6.

**Pieza de altitud:** política general de error del pipeline de pull. El motor (`leulit_pipeline_pattern`) ya distingue `isBlocking=true` (aborta → `PipelineFailure`) de `isBlocking=false` (emite evento error, continúa con fallback). Pero `PullCoordinator` (1) ignora `PipelineFailure` no-401 (NF-1), (2) no recolecta errores no bloqueantes (NF-2/NF-3), (3) `UpdatePullStateTask`+`pull_state` no representan error/partial (NF-5), (4) `DispatchPullCompletedTask` siempre dispara "completado limpio" (NF-6).

> `[REVIEW G2 — corrección crítica]` **Verificado:** `TaskPipeline` defaulta a `StreamController()` single-subscription (`task_pipeline.dart:37-40`); soporta `broadcast: true`. Los eventos se emiten síncronamente dentro de `run()` vía `_emit`, **pero los callbacks de `.listen()` corren en microtasks posteriores**. Si WS4 lee `ctx.partialErrors`/`ctx.outcome` inmediatamente tras `await pipeline.run(...)`, los eventos de error pueden no haberse procesado → pulls degradados mal clasificados como limpios. **Decisión: el try/catch por-item (PASO 1) es el mecanismo PRIMARIO** (muta `ctx` síncronamente, sin race). La suscripción a `pipeline.events` es opcional y solo correcta si se `await`-ea el drenaje del stream antes de leer `ctx` (esperar `PipelineEventType.pipelineEnd` con un Completer). Construir con `TaskPipeline(broadcast: true)` para evitar "Stream already listened to" al combinar suscripción + dispose.

**PASO 1 — `PullContext` acumula errores no bloqueantes (NF-2/NF-3).** `pull_context.dart`:
```dart
final List<PullTaskError> partialErrors = [];
bool get hasPartialErrors => partialErrors.isNotEmpty;
// + class PullTaskError { final String taskName; final Object error; ... }
```
- NF-2: `upsert_non_conflicting_task.dart:25-44` — try/catch por-item; en fallo `ctx.partialErrors.add(PullTaskError('UpsertNonConflicting', e))` + `continue` (persiste N-1, no aborta el bucle).
- NF-3: `enqueue_conflicts_task.dart:33-58` — try/catch por-item alrededor de `db.insert`+dispatch; en fallo añade a `partialErrors` + `continue`.
- **El try/catch envuelve solo la persistencia, NO el chequeo de cancelación cooperativa** (`isCancelRequested`).

**PASO 2 — `PullOutcome`.** `lib/core/sync/pull/pull_outcome.dart` (NEW): `enum PullOutcome { ok, okWithConflicts, partial, error, cancelled, authExpired }`. Mapeo a string snake_case para `last_status` (`ok`/`ok_with_conflicts`/`partial`/`error`/`cancelled`/`auth_expired`).

**PASO 3 — `PullContext` lleva desenlace + mensaje.** `pull_context.dart`: `Object? blockingError;`, `bool authExpired = false;`, getters `errorMessage` y `outcome` (precedencia: authExpired > blockingError > cancelled > partial > okWithConflicts > ok).

**PASO 4 — `UpdatePullStateTask` consume el outcome real (NF-5).** `update_pull_state_task.dart:27-41`: escribir `last_status` = `outcome` mapeado, `last_error = ctx.errorMessage`. **`[REVIEW]` Extraer un único `static writePullState(db, entityType, outcome, errorMessage)` reusado por la task Y el coordinator (DRY, una fuente del mapeo).**

**PASO 5 — `PullCoordinator` política central (NF-1/NF-6).** `pull_coordinator.dart`:
- (a) Suscribir a `pipeline.events` ANTES de `run()` como belt-and-suspenders, **esperando `pipelineEnd` antes de leer ctx**; filtrar `AuthExpiredException`.
- (b) Tras `result = await pipeline.run(...)`: si `result.isFailure`: 401 → `ctx.authExpired=true`, dispatch `SyncActions.authExpired`, `writePullState('auth_expired')`; else (NF-1) → `ctx.blockingError = result.errorOrNull`, `writePullState('error')` con `last_error`. **Esto resuelve NF-1: un fallo bloqueante deja de ser "PullSummary vacío == éxito".**
- (c) Construir SIEMPRE `PullSummary` desde ctx (un return al final). Cancelar suscripción en `finally`; `pipeline.dispose()` en `finally` (hoy se llama en ramas distintas — limpiar, una vez).
- (d) NF-6: un fallo BLOQUEANTE aborta antes de `DispatchPullCompletedTask` → NO se dispara `cloudPullCompleted` (correcto). El caso PARTIAL sí se dispara con `outcome=partial`.

**PASO 6 — `PullSummary` expone desenlace.** `pull_coordinator.dart:18-32`: `final PullOutcome outcome; final String? errorMessage; bool get isDegraded => outcome == error || outcome == partial;`. Mantener `total/upserted/conflicts/cancelled/authExpired` por compat (controller `:216,:227`). `authExpired` pasa a `outcome == authExpired`.

**PASO 7 — `CloudPullCompletedEvent` lleva outcome (NF-6).** `sync_actions.dart:57-69` + `dispatch_pull_completed_task.dart:20-27`: añadir `final PullOutcome outcome; final String? errorMessage;`.

**PASO 8 — el controller surface la degradación (NF-1/NF-6).** `sincronizacion_controller.dart:211-242`, tras los if de cancelled/authExpired, ANTES de marcar success:
```dart
if (summary.isDegraded) {
  _updateRow(kind, _rowFor(kind).copyWith(
    status: MasterDataStatus.error,
    errorMessage: summary.outcome == PullOutcome.error
      ? 'No se pudo descargar la lista: ${summary.errorMessage ?? 'error desconocido'}'
      : 'Descarga incompleta: algunos elementos no se guardaron. ${summary.errorMessage ?? ''}',
    clearProgress: true, clearProgressLabel: true));
  return; // NO persistir lastDownload ni marcar success
}
```
`[REVIEW G5]` **Este branch va ANTES del gating de cache de WS5 en el mismo success-tail.** Orden de edición: WS4 inserta `isDegraded` return primero; WS5 superpone el source-gating después (la suposición de WS5 "segmentos siempre persiste timestamp" solo es válida tras el bail de WS4).

> **Schema (verificado):** `pull_state.last_status` y `last_error` ya existen (`offline_database.dart:106-113`). Sin migración; solo cambian los valores escritos. Sin CHECK constraint sobre `last_status`.

**Ficheros tocados:** `pull_context.dart`, `pull_outcome.dart` (NEW), `pull_coordinator.dart`, `upsert_non_conflicting_task.dart`, `enqueue_conflicts_task.dart`, `update_pull_state_task.dart`, `dispatch_pull_completed_task.dart`, `sync_actions.dart`, `sincronizacion_controller.dart`.

**Tests nuevos:** `test/core/sync/pull/pull_coordinator_test.dart` (ffi + mocktail):
- NF-1: fetcher lanza `Exception('boom')` no-auth → `outcome==error`, `errorMessage` contiene 'boom', `isDegraded`, `pull_state.last_status=='error'` + `last_error`.
- NF-1 auth: fetcher lanza `AuthExpiredException` → `outcome==authExpired`, `pull_state=='auth_expired'`, `SyncActions.authExpired` 1 vez.
- NF-2: `store.upsert` lanza en el 2º de 3 → `outcome==partial`, persiste items 1 y 3 (`upserted==2`), `partialErrors` con 'UpsertNonConflicting', `pull_state=='partial'`.
- NF-3: `db.insert` de sync_conflicts falla → `outcome==partial`, `partialErrors` con 'EnqueueConflicts'; los insertados sí están.
- NF-5: con conflictos → `okWithConflicts`, `last_error==null`; limpio → `ok`, `last_error==null`.
- NF-6: fallo bloqueante → `cloudPullCompleted` NUNCA se dispara; partial → se dispara con `event.outcome==partial`.
- `test/presentation/sincronizacion/sincronizacion_controller_pull_test.dart`: `isDegraded` → fila `MasterDataStatus.error` + errorMessage, NO se llama `_persistLastDownload`.

**Criterios de aceptación:** ver tests. La política es genérica (entidad pulleable nueva hereda desenlace tipado sin tocar `PullCoordinator`). `flutter analyze --fatal-infos` limpio; ambos branches de error manejados.

**Riesgos de regresión:** `sincronizacion_controller:211-254` es el ÚNICO consumidor de `PullSummary` (`OfflineModule.runPull`); el branch `isDegraded` es obligatorio (sin él la fila se pone verde pese a `pull_state='error'`). `OfflineModule.runPull` devuelve `Future<PullSummary?>` — `null` significa "sin fetcher", NO error de pull; el error viaja DENTRO de `PullSummary.outcome`. `CloudPullCompletedEvent` gana campos `required` → actualizar el único dispatch (`dispatch_pull_completed_task.dart:21`). Mover `dispose()` a finally — cancelar suscripción antes para evitar "add after close".

**Dependencia de backend:** ninguna.

**Decisiones abiertas:** NF-2/NF-3 → **try/catch por-item** (semántica master-data: "persistir todo lo persistible y reportar lo que no"). `writePullState` reusado vía estático (DRY). Suscripción a events → **belt-and-suspenders, esperando pipelineEnd** `[REVIEW G2]`. Strings → **snake_case**. Mensaje partial → genérico en fila + detalle en `last_error`.

---

### WS3 — Detalle local-only + preservación de estado de sync
**Cubre:** #4, NF-11, NF-P, NF-10.

**#4 — `guardar()` descarta edición local-only + toast falso.** `segmento_detalle_controller.dart:343-369`. Bloque 348-354 (con guard `if (segmento.id != null)`) → escritura INCONDICIONAL, eliminar `updateEstado` (redundante: `saveLocal` ya persiste `estado` vía `_entityToRow`, y `SegmentoRepositoryImpl.saveLocal:60-64` ya ramifica `create()`/`update()` por `id==null`):
```dart
segmento.estado = estado.value;
segmento.tipoActividad = tipoActividad.value;
segmento.descripcion = descripcion.value;
await _segmentoRepo.saveLocal(segmento);
```
El `try/catch` envolvente (347-368) ya muestra snackbar de error → el toast de éxito (355-359) deja de mentir. **Hermano:** `edit_extremos_controller.dart:204-206` `if (updated.id != null) await _repo.saveLocal(updated);` → mismo descarte; quitar el guard.

**NF-11 — `updateEstado` solo `findByRemoteId`.** Tras #4 el único caller en producción desaparece; queda `UpdateSegmentoEstadoUseCase` (con tests) que recibe `int id` y por firma no representa local-only. **No cambiar firma** (YAGNI). El método ya devuelve `DataResult.failure(404)` cuando no encuentra fila (fallo tipado, no éxito silencioso). Añadir DartDoc en `:77`: "solo para segmentos con id remoto; local-only usa saveLocal".

**NF-P — `_addImagen` descarta foto si `id==null`.** `segmento_detalle_controller.dart:259-273`, línea 261 `if (segId == null) return;` pierde la foto (ya escrita a disco) sin feedback. La imagen se identifica por su `clientId`; no necesita el id remoto del segmento para persistir. Reescribir para persistir SIEMPRE con try/catch y feedback:
```dart
Future<void> _addImagen(String localPath, TipoFoto tipo) async {
  final imagen = ImagenSegmentoEntity(
    actividadId: 0, segmentoId: segmento.id ?? 0, // FK por id remoto (A4 migrará a clientId)
    tipoFoto: tipo, filename: localPath.split('/').last,
    ruta: localPath, capturadaAt: DateTime.now(),
  );
  try { await _imagenRepo.saveLocal(imagen); await _loadImagenes(); }
  catch (e) { _showSnack(title: 'Error', message: 'No se ha podido guardar la foto: $e', isError: true); }
}
```
**Visualización en local-only diferida (ver decisión abierta):** `_loadImagenes:107-118` filtra por `segmento.id` (null en local-only) → la foto persistida no se ve hasta tener id remoto. El 🔴 (pérdida de dato) queda resuelto; la visualización se cierra con A4.

**NF-10 — `synced_at` se borra en cada edición (GENERALIZAR INFRA).** `synced_at` solo vive en DB (lo escriben `markSynced` y el upsert de pull); no es campo de la entidad en memoria. `ConflictAlgorithm.replace` (DELETE+INSERT) + `_entityToRow` sin `synced_at` → cada edición borra `synced_at`. Afecta segmento, mensaje e imagen (verificado: `imagen.toMap()` omite `synced_at`; mismo bug latente).
- **Segmento:** ya resuelto por la reconciliación de **WS2 STEP 5** (update-then-insert preserva `synced_at`). WS3 NO re-toca el upsert de segmento.
- **Mensaje e imagen:** aplicar el mismo patrón update-then-insert que preserva `synced_at`. **`[REVIEW G3]` Nota: `imagen.toMap()` incluye `needs_sync: 1`** → el UPDATE-branch resetea `needs_sync→1` en cada edición. Es defendible (edit = dirty) pero es un cambio de comportamiento sin marcar — **confirmar intención** (decisión abierta).
- **Helper compartido (mixin)** `RowUpsertMixin` en `lib/core/sync/contracts/` con `upsertPreserving(DatabaseExecutor exec, {required String table, required Map<String,Object?> row, required String clientId})` que los stores `with`. Cumple el test de extensibilidad. **Debe recibir el `DatabaseExecutor txn`** para no romper atomicidad (`OfflineRepository._persistAndEnqueue:53-62` pasa txn).

**Ficheros tocados:** `segmento_detalle_controller.dart`, `edit_extremos_controller.dart`, `segmento_repository_impl.dart` (DartDoc :80 — coordinar con WS2), `mensaje_local_store.dart`, `imagen_local_store.dart`, `local_store.dart` (mixin).

**Tests nuevos:**
- `test/data/sync/segmento_local_store_test.dart`: (a) entidad nueva → `synced_at` NULL; (b) `markSynced` setea no-null; (c) **tras markSynced, segundo upsert mutando estado PRESERVA `synced_at`** (núcleo NF-10).
- `test/data/sync/mensaje_local_store_test.dart`: replica NF-10.
- `test/data/sync/imagen_local_store_test.dart`: NF-10 + verifica el comportamiento de `needs_sync` tras edición (según decisión).
- `test/data/repository/segmento_repository_impl_test.dart`: (a) saveLocal id==null → create + job 'create'; (b) id!=null → update + job 'update'; (c) `updateEstado(idInexistente)` → `failure(404)`.
- `test/presentation/detalle/segmento_detalle_controller_test.dart`: (a) #4 guardar con id==null → `saveLocal` 1 vez, `updateEstado` NUNCA, snackbar éxito; (b) estado no editable → diálogo; (c) NF-P `_addImagen` con id==null → `saveLocal` llamado; (d) saveLocal lanza → snackbar error.
- `test/presentation/detalle/edit_extremos/edit_extremos_controller_test.dart`: guardar con id==null → `saveLocal` llamado.

**Criterios de aceptación:** `guardar()` persiste estado/tipo/descripción con id==null + solo toast de éxito si no lanzó; `grep` 0 referencias a `updateEstado` en el controller; foto en local-only inserta fila + job + feedback ante fallo; tras markSynced editar conserva `synced_at`; `updateEstado(idInexistente)` → 404; edit_extremos persiste con id==null.

**Riesgos de regresión:** cambiar upsert de mensaje/imagen afecta todos los callers (motor pull + `OfflineRepository.create/update`) — verificar que el pull sigue sobrescribiendo campos de negocio (sí, el UPDATE incluye todos los `_entityToRow`, solo deja `synced_at`). `insert(ignore)+update` = 2 sentencias dentro de `db.transaction` (coste despreciable). Quitar guard en edit_extremos: local-only ahora encola create/update — el outbox `UNIQUE(entity_type,client_id,operation)` colapsa doble-create. `updateEstado` sigue en interface + `UpdateSegmentoEstadoUseCase` + tests: no cambiar firma. `_loadImagenes` sigue filtrando por `segmento.id` (visualización local-only diferida).

**Dependencia de backend:** ninguna. A4 (FK imagen por clientId) y BE-3/BE-4 son prerequisitos para asociación correcta tras primer sync, fuera de alcance.

**Decisiones abiertas:** mixin `RowUpsertMixin` en `contracts/` → **sí** (extensibilidad). Visualización local-only de foto → **(a) diferir a A4** (el 🔴 ya resuelto). `updateEstado` mantener → **sí** (DartDoc + quitar caller). NF-10 a `position_local_store` → **incluir si se adopta el mixin** (coordinar con WS6 para no solapar fichero). **`needs_sync` reset en imagen UPDATE → confirmar con producto** `[REVIEW G3]`.

---

### WS5 — Master-data y controlador de sincronización
**Cubre:** NF-12, NF-13, NF-14, NF-15, A3.

**Causa raíz compartida:** `GasoductosService._runOnce:144` y `PksService._runOnce:123` terminan en `catch (e) { debugPrint(...) }` y devuelven `Future<void>` SIN señal de desenlace → el controller `_runOne:184/195` no ve throw, cae al success verde (`:243-254`) con timestamp fresco. El `void` también oculta si hubo fetch real o cortocircuito a cache (NF-14).

**STEP 1 — Tipo de desenlace compartido.** `lib/core/services/master_data_load_result.dart` (NEW):
```dart
enum MasterDataSource { network, cache, empty }
class MasterDataLoadResult { final MasterDataSource source; final int itemCount; const MasterDataLoadResult(this.source, this.itemCount); }
```

**STEP 2 — NF-12 + NF-14 en ambos services.** `gasoductos_service.dart`/`pks_service.dart`: `reload()`/`_runOnce()` → `Future<MasterDataLoadResult>`. **Eliminar el `catch (e) { debugPrint }`** (gasoductos :144-145, pks :123-124) para que las excepciones propaguen. **Mantener el `finally`** (reset de estado). Branches: offline/cache-hit → `MasterDataLoadResult(cache, n)`; network end → `MasterDataLoadResult(network, fetched)` (capturar `_entitiesBuffer.length` en local ANTES del `finally`). Mantener el try/catch por-fichero de `_onGeoJsonLoaded` (resiliencia de parse, único catch superviviente).

**STEP 3 — NF-13 (CancelToken en reload).** Añadir `CancelToken? token` a `reload`/`_runOnce` de ambos services y a `JsonLoaderService.loadFiles`/`_runFiles`. En `_runFiles` chequear `token?.isCancelled` al entrar (cortocircuito a `geoJsonLoadCompleted`); en el service re-chequear tras `await _loader.loadFiles(...)` antes de `assignAll`. Controller pasa `sharedToken`: `_gasoductos.reload(token: sharedToken)` (:184), `_pks.reload(token: sharedToken)` (:195).

**STEP 4 — NF-12/14 en el controller.** Capturar `final res = await _gasoductos.reload(token: sharedToken)`. El `catch` del controller (`:255-266`) ya existe → un 500/parse-fail aterriza en `MasterDataStatus.error` sin branches extra (NF-12). NF-14: añadir `bool servedFromCache` a `MasterDataRow` (`sync_models.dart`, default false, vía `copyWith` con patrón clearX). En el success-tail (`:243-254`), `servedFromCache = res.source == cache`. **Persistir `lastDownloadAt` SOLO si `source == network`** (cache no es descarga fresca). `[REVIEW G5]` **Este gating va DESPUÉS del branch `isDegraded` de WS4** (orden de edición: WS4 primero; el "segmentos siempre persiste" de WS5 solo aplica tras el bail degradado). UI: hint "desde caché" en `sincronizacion_page.dart` cuando `servedFromCache`.

**STEP 5 — NF-15 (`_initRows` no awaited).** `myOnInit:62` llama `_initRows()` fire-and-forget; `rows` vacío hasta resolver prefs → `_rowFor:136` (`firstWhere` sin orElse) lanza `StateError`. Defensa en profundidad:
- (a) `_rowFor` total: `firstWhere(..., orElse: () => MasterDataRow(kind: kind))`.
- (b) **`[REVIEW G12]` Guard en AMBOS entry points** (`descargarTodo:83`, `descargar:105`): `if (rows.isEmpty) return;` — el guard es el fix real; el `orElse` solo no basta (`descargarTodo` iteraría construyendo rows default contra estado de timestamp no inicializado). Botón UI deshabilitado mientras `rows.isEmpty`/`isWorking`.

**STEP 6 — A3 (ship-blocker-later, shim ahora).** `local_database.dart:68-98` crea `gasoductos`/`pks` con `CREATE TABLE IF NOT EXISTS` FUERA de `_entity_schema_version`; el `_onUpgrade` global borrado ya mutó `gasoductos.ct TEXT→ct_id INTEGER` sin path de migración. **Shim de migración versionada ahora** (bajo riesgo, quita el footgun de deploy): mover los dos `CREATE TABLE` a funciones de migración versionadas keyed en `_entity_schema_version` vía `OfflineDatabase.migrateEntity` con un shim shape-`LocalStore` (entityType 'gasoducto'/'pk', schemaVersion 1, `migrate(from==0)` crea la tabla verbatim), SIN enrutar lecturas por él (los readers raw-SQL de los services siguen). TODOs `// A3 ship-blocker-later`. Promoción completa a `LocalStore<T>` read-path diferida. **Mantener `IF NOT EXISTS` durante el interino** (NF-19: todos los CREATE usan IF NOT EXISTS hoy).

**Ficheros tocados:** `master_data_load_result.dart` (NEW), `gasoductos_service.dart`, `pks_service.dart`, `json_loader_service.dart`, `sincronizacion_controller.dart` (branch master-data), `sync_models.dart`, `sincronizacion_page.dart`, `local_database.dart` (A3), `app_di.dart` (A3 shim).

**Tests nuevos:**
- `test/presentation/sincronizacion/sincronizacion_controller_test.dart` (mocktail): (1) `reload` lanza → fila `error`, `lastDownloadAt` NO avanza (NF-12); (2) `reload` → `cache` → success pero `servedFromCache==true`, timestamp NO avanza (NF-14); (3) `reload` → `network` → success, `servedFromCache==false`, timestamp avanza y persiste (NF-14 inverso); (4) `descargar` antes de `_initRows` (rows vacío) no lanza StateError, no-op (NF-15); (5) `cancelar()` durante `descargarTodo` pasa token cancelado a `reload` (NF-13, capturar token).
- `test/core/services/gasoductos_service_test.dart` (ffi + mock loader/connectivity): (a) offline → `cache`, no llama loader; (b) online con loader que lanza → `_runOnce` RETHROWS; (c) cache-hit → `cache`; (d) network OK → `network` con itemCount. Espejo para PksService.
- `test/data/services/json_loader_service_test.dart`: `loadFiles(token: cancelled)` cortocircuita sin gets de red.
- `test/data/local/local_database_migration_test.dart` (ffi, A3): apertura idempotente; `_entity_schema_version` tiene 'gasoducto'/'pk'; from==0 crea tablas con `ct_id INTEGER`.

**Criterios de aceptación:** 500/parse error → fila `error` + mensaje, NO avanza `lastDownloadAt` (NF-12); sin catch-debugPrint que trague (solo el por-fichero); cache → success + `servedFromCache==true` + timestamp sin cambiar (NF-14); network → timestamp avanza + persiste + `servedFromCache==false`; `cancelar()` propaga token cancelado (NF-13); descargar antes de `_initRows` no lanza StateError, no-op (NF-15); A3 TODOs + shim versionado.

**Riesgos de regresión:** `mapa_global_controller.dart:199/217` llaman `reload()` y dependen de que NO lance en happy path; tras NF-12 puede lanzar — el try/catch existente (`:197-209`/`:215-226`) lo maneja (ver decisión abierta sobre `ensureLoaded`). Cambio `Future<void>→Future<MasterDataLoadResult>` source-compatible para `await reload();` que ignora el resultado (verificado: solo usos await-and-ignore). `servedFromCache` en `copyWith` debe seguir el patrón clearX. A3 shim toca orden de arranque de `OfflineDatabase`/`app_di` — correr ANTES de `_createMasterDataTables` o reemplazarlo; mantener `IF NOT EXISTS`.

**Dependencia de backend:** ninguna. A3 completo y el REST único (§12.2) ortogonales y no requeridos.

**Decisiones abiertas:** `ensureLoaded()` vs `reload()` política de error → **solo `reload()` propaga** (path iniciado por usuario); `ensureLoaded()` (prefetch pasivo) sigue best-effort logueado. NF-14 surface → **flag `servedFromCache`** (no nuevo enum status). A3 → **shim versionado ahora** + promoción diferida. CancelToken → **mínimo** (entrada de `_runFiles` + re-check) con TODO per-fichero. `lastDownloadAt` en cache → **NO avanzar** (debe significar "último fetch real de red").

---

### WS6 — GPS: pérdida de tramos, atribución, timestamps
**Cubre:** NF-7, NF-8, NF-9, A6, NF-23, NF-24.

**Contexto verificado:** `OfflineRepository.create()` (`:30,:53-63`) envuelve store.upsert + outbox.enqueue en `_db.transaction` → atómico. Si `create()` lanza, no queda fila ni en store ni en outbox → el re-encolado de NF-7 es RESTAURAR el buffer en memoria. `Position.timestamp` es NON-NULLABLE en geolocator 14. `user_id` (int) lo escribe `auth_repository_impl.dart:30` en login, lo borra `:44` logout.

**NF-7 — escribir-luego-limpiar + re-encolar en fallo.** `gps_background_service.dart:135-158` `_flushIfNotEmpty`:
```dart
Future<void> _flushIfNotEmpty({required bool forceClose}) async {
  if (_flushing) return;            // [REVIEW G4] mutex no-reentrante
  if (_buffer.isEmpty) return;
  _flushing = true;
  try {
    final points = List<PositionPoint>.unmodifiable(_buffer); // snapshot, NO clear aún
    final (startedAt, endedAt) = _deriveInterval(points);     // A6
    final batch = PositionBatchEntity(operadorId: _operadorId!, points: points, startedAt: startedAt, endedAt: endedAt);
    await _offline.create(batch);                 // 1) persistir PRIMERO
    _buffer.removeRange(0, points.length);         // 2) limpiar solo lo confirmado
    lastFlushAt.value = DateTime.now();
    lastError.value = null;
  } catch (e) {
    lastError.value = 'Error guardando lote GPS: $e'; // buffer intacto = re-encolado (tx atómica)
    if (kDebugMode) debugPrint('GpsBackgroundService flush error: $e');
  } finally {
    _flushing = false;
  }
}
```
`[REVIEW G4 — corrección crítica]` **Mutex `bool _flushing` OBLIGATORIO.** Verificado: `_flushIfNotEmpty` se invoca `unawaited` desde timer (`:74`) Y desde threshold 500 (`:124`), sin guard de re-entrancia. Bajo dos flushes solapados, `removeRange(0, points.length)` keyed a un snapshot length elimina el rango EQUIVOCADO (flush B borra índices que ahora apuntan a puntos nuevos no enviados) → pérdida silenciosa, el mismo bug que NF-7 dice arreglar. El mutex (sin `await` entre check y set, single-isolate seguro) es mandatorio. `removeRange` (no `clear()`) preserva puntos llegados durante el `await`.

**NF-8 — flush garantizado al salir.** `GetxService.onClose` es void (no se puede await). `GpsBackgroundService` es `permanent:true` (`app_di.dart:110`) → su `onClose` solo corre al cerrar la app; el verdadero punto es el `onClose` de `MapaGlobalController:84` (`unawaited(stop())`). Como el servicio sobrevive al dispose del controller, el flush continúa en background. **Decisión (ver abierta):** añadir `Future<void> stopTracking() => Get.find<GpsBackgroundService>().stop();` en `MapaGlobalController` y llamarlo awaited desde un `PopScope`/handler de salida del mapa; `onClose` mantiene `unawaited(stop())` como red. En el servicio, `stop()` ya hace flush final antes de `state=stopped` (`:103`) y es idempotente (guard `:97`); con NF-7 el flush final ya no pierde por orden.

**NF-9 — abortar si operadorId inválido.** `gps_background_service.dart:43 int _operadorId = 0;` → `int? _operadorId;`. `_readOperadorId` → `prefs.getInt(_prefsUserIdKey)` (sin `?? 0`). En `start()` tras leer, si `null || <= 0`: `lastError.value = 'No hay operador en sesión; no se inicia el tracking GPS.'`, parar FGS si arrancó, `return` (state queda stopped). Mover la lectura ANTES de `_startAndroidForegroundService()`. En flush usar `_operadorId!` (garantizado tras abort; defensivo: si null, saltar + log).

**A6 — derivar intervalo de tiempos de captura (clamp + UTC).** Helper que reemplaza `:138-139`:
```dart
(DateTime, DateTime) _deriveInterval(List<PositionPoint> pts) {
  final caps = pts.map((p) => p.capturedAt.toUtc()).toList();
  var start = caps.first; var end = caps.last;
  for (final c in caps) { if (c.isBefore(start)) start = c; if (c.isAfter(end)) end = c; }
  if (end.isBefore(start)) end = start;
  return (start, end);
}
```
Eliminar `_bufferStartedAt` del cálculo (reloj de sistema). Normalizar `capturedAt` a UTC en `_onPosition:116` (`capturedAt: p.timestamp.toUtc()`) para coherencia store/JSON/derivación. `PositionBatchEntity.toJson():81-82` ya hace `toIso8601String()` → con UTC lleva sufijo Z (cumple contrato).

**NF-23 — `findAll` N+1 → 2 queries.** `position_local_store.dart:147-165`: query de todos los batches (`started_at DESC`) + UNA query de todos los puntos (`captured_at ASC`) + agrupar en memoria por `batch_client_id`. Orden de puntos garantizado por `ORDER BY captured_at ASC` global.

**NF-24 — no fabricar `updatedAt` en parse fallido.** `position_local_store.dart:211-213`: si `updated_at` no parsea, NO pasar null silencioso (el constructor `:56 updatedAt ?? DateTime.now()` fabricaría now()). Loguear (kDebugMode) + fallback DETERMINISTA `endedAt` (ya parseado). El constructor `?? now()` se mantiene (solo aplica a creación genuina; la columna es NOT NULL).

**Ficheros tocados:** `gps_background_service.dart`, `position_local_store.dart`, `mapa_global_controller.dart`, `position_batch_entity.dart` (revisión, probablemente sin cambios).

**Tests nuevos:** `test/data/sync/position_local_store_test.dart` (ffi) + `test/core/services/gps_background_service_test.dart` (mocktail):
- NF-23: 3 batches con 4/0/5 puntos → `findAll()` agrupa y ordena correctamente (batches DESC, puntos ASC).
- NF-24: fila con `updated_at='basura'` → `updatedAt == endedAt` (no ~now()).
- Roundtrip: upsert→findByClientId, `startedAt.isUtc` tras roundtrip.
- NF-7: `create()` stub LANZA → `lastError` no-null + segundo flush exitoso envía TODOS los puntos originales (escribir-luego-limpiar). Caso puntos concurrentes: punto nuevo durante el `create()` sobrevive.
- **NF-7 mutex:** dos `flushNow()` solapados (Completer pendiente) → el segundo retorna inmediato (`_flushing`), sin doble-envío ni pérdida `[REVIEW G4]`.
- NF-9: `setMockInitialValues({})` → `start()` deja state==stopped, `lastError` menciona operador, `verifyNever(create)`. user_id=0 → mismo aborto.
- A6: puntos con capturedAt desordenados/local → flush → captura batch: `startedAt<=endedAt`, ambos `.isUtc`, min/max de capturedAt UTC.
- Exponer `@visibleForTesting Future<void> flushNow() => _flushIfNotEmpty(forceClose:false);` + setter de buffer.

**Criterios de aceptación:** ver tests. NF-7 cero pérdida + mutex; NF-8 flush antes de stopped + punto de salida que await-ea stop; NF-9 nunca batch con operador 0; A6 start/end de capturedAt en UTC, `start<=end`; NF-23 2 queries constantes; NF-24 sin now() fabricado, log + fallback determinista.

**Riesgos de regresión:** `GpsBackgroundService` permanent + start/para desde `MapaGlobalController.onInit/onClose` — abortar en start sin sesión válida deja el mapa sin tracking silenciosamente → exponer `lastError` en UI del mapa (NF-9 exige aviso). `findAll()` consumido vía `OfflineRepository<PositionBatchEntity>` — sin callers de producción hoy (push-only); cambio transparente. Normalizar capturedAt a UTC cambia `posiciones_gps.captured_at` (antes local) — sin datos legacy (app no en producción). `removeRange` asume buffer crece por la cola (cierto: `_onPosition` hace `add`) — documentar invariante.

**Dependencia de backend:** ninguna nueva. Contrato existente `POST /positions/batch` idempotente por `batch_client_id` (BE-6). A6 refuerza el cumplimiento de "updated_at/timestamps ISO8601 UTC" desde el cliente.

**Decisiones abiertas:** NF-8 punto de await → **`stopTracking()` desde PopScope** + `onClose` red de seguridad. A6 eliminar `_bufferStartedAt`/`forceClose` → **sí eliminar `_bufferStartedAt`**; revisar si `forceClose` queda sin uso. Normalizar UTC en captura → **sí** (coherencia total). NF-9 avisar al usuario → **abortar + exponer `lastError`** en el mapa. Testabilidad → **`@visibleForTesting flushNow()`**. NF-23/24 generalizar → **NO ahora** (YAGNI); documentar regla "parse fallido → log + fallback determinista, nunca now()" en CLAUDE.md Lecciones.

---

### WS7 — Mensajes offline-first
**Cubre:** NF-16, NF-17, NF-18.

Todo en `lib/data/repository/mensaje_segmento_repository.dart` `mensajesBySegmento()` (`:40-75`) y `_mergeWithPending()` (`:101-112`). Causa compartida con #2: `MensajeSegmentoEntity.fromJson` re-acuña UUID cuando el backend omite `client_id` (entity:48 → constructor:18).

**NF-16 — servir cache ante CUALQUIER fallo de lectura.** Hoy solo `on NetworkError` (`:58`) sirve cache; el `catch (e)` genérico (`:68`) devuelve `failure(500)` sin cache, y ESE branch es alcanzable (`fromJson` puede lanzar, `data is! List` `:46` devuelve failure desnudo). Refactor a helper compartido por ambos catch:
```dart
} on NetworkError catch (e) {
  return _serveCacheOrFail(id, reason: 'red', message: e.message, statusCode: e.statusCode ?? 503, cause: e);
} catch (e) {
  return _serveCacheOrFail(id, reason: 'inesperado', message: '$e', statusCode: 500, cause: e);
}
// + el early-return data is! List (:46-51) también enruta por _serveCacheOrFail
```
`_serveCacheOrFail` lee `_localStore.findBySegmento(id)`; si el store lanza → `DataResult.failure` con mensaje + cause; si no → `DataResult.success(local)` (NF-17: cache vacía es éxito vacío). **`[REVIEW G6]` El "log de forma inesperada" usa `AppLog` (de WS0) — dependencia cross-WS: WS7 requiere que WS0 haya introducido `AppLog`** (`debugPrint` se strippea en release). Sin AppLog, el `data is! List` que sirve cache enmascararía una regresión de contrato silenciosamente.

**NF-17 — cache vacía → éxito vacío.** Resuelto por el helper: el viejo `if (local.isNotEmpty) return success; return failure(503);` → `success(local)` incondicional. Lista vacía = "este segmento no tiene mensajes", no error rojo. Simetría online/offline.

**NF-18 — dedup fiable independiente del clientId re-acuñado.** Reescribir `_mergeWithPending` con clave en cascada que sobrevive al re-mint:
```dart
String _dedupKey(MensajeSegmentoEntity m) =>
    m.id != null ? 'r:${m.id}' : 'c:${m.segmentoId}|${m.mensaje}|${m.createdAt.toUtc().toIso8601String()}';

List<MensajeSegmentoEntity> _mergeWithPending(remote, local) {
  final remoteClientIds = remote.map((m) => m.clientId).toSet();
  final remoteKeys = remote.map(_dedupKey).toSet();
  final pendingOnly = local.where((m) =>
      m.id == null && !remoteClientIds.contains(m.clientId) && !remoteKeys.contains(_dedupKey(m))).toList();
  return pendingOnly.isEmpty ? remote : [...pendingOnly, ...remote];
}
```
El check de clientId es fast-path (funciona cuando el backend echo client_id, BE-2); el fingerprint `(segmentoId|mensaje|createdAt-UTC)` es el puente interino. `createdAt` (cliente, round-tripped) es estable en el ciclo send→echo si el backend preserva `created_at`.

**Ficheros tocados:** `mensaje_segmento_repository.dart` (+ su test). **Ningún engine/store/adapter/entity** (contención — pasa el test de extensibilidad).

**Tests nuevos:** `test/data/repository/mensaje_segmento_repository_test.dart` (mocktail NetworkService + MensajeLocalStore):
- NF-16a: `get` lanza Exception genérica → `DataSuccess` con cache.
- NF-16b: 200 con body no-List → `DataSuccess` con cache.
- NF-16c: `fromJson` lanza en un elemento → fallback a cache success.
- NF-16d: NetworkError(offline) Y store lanza → `DataFailure` (único path irrecuperable).
- NF-17a: offline + cache vacía → `DataSuccess([])`.
- NF-17b: online, remote y local vacíos → `DataSuccess([])`.
- NF-18a: remote con mismo contenido pero clientId distinto que local pending → 1 copia.
- NF-18b: remote echo con `id` matching, local pending id==null → dedup por `r:<id>`.
- NF-18c: local pending no presente en remote → SÍ se prepende (sin falso-positivo).
- NF-18d: backend echo client_id matching → dedup por fast-path.

**Criterios de aceptación:** `mensajesBySegmento` NUNCA devuelve `DataFailure` mientras el store sea legible; cache vacía → `DataSuccess([])`; `DataFailure` solo si red falla Y store lanza (con mensaje + cause real); enviar offline + recargar tras sync → 1 copia aunque el backend omita client_id; pending distinto sigue mostrándose; ningún engine/store/adapter/entity cambiado.

**Riesgos de regresión:** único caller `segmento_detalle_controller.dart:281` (`_loadMensajes`) ya maneja `dataOrNull ?? []` — verificar panel con empty state sano. Optimistic-insert (`sendMensaje:300-320`): el reload lee del store (reemplaza la copia optimista entera) — bajo riesgo, NF-18c lo cubre. Fingerprint podría falso-positivo colapsar dos mensajes idénticos en el mismo segundo del mismo operador (improbable con ms); mitigado con ISO8601-ms si el backend lo preserva. `data is! List`→cache enmascara regresión de contrato (intencional offline-first, pero loguear vía AppLog).

**Dependencia de backend:** **BE-2** (echo `client_id` en POST/GET mensajes + preservar `created_at`). Puente interino: `_dedupKey` en cascada funciona hoy sin backend.

**Decisiones abiertas:** granularidad fingerprint → **ISO8601-ms ahora**; si el backend trunca/omite `created_at`, fallback a `(segmentoId|mensaje|enviadoPor)` (NO bare `(segmentoId|mensaje)`). `data is! List` → **servir cache + log** (offline-first gana, contrato observable vía log). Failure 503 vs 500 → **statusCode de red** (cause = network). Generalización → **contener en el repo de mensaje** (no generalizar fingerprint a infra; el path de segmentos lo cubre WS2).

---

### WS9 — Limpieza y deduplicación
**Cubre:** #8, A1, A2, NF-25, DC.

> Estrictamente **último**: toca los ficheros que cada WS previo estabiliza.

**BLOQUE 1 — #8: `findWhere` genérico + borrar `getPendingBySegmento` muerto.**
- `local_store.dart` (tras `findAll()`): `Future<List<T>> findWhere(String column, Object? value);` `[REVIEW G7]` **doc-comment: `column` DEBE ser literal de código, nunca input de usuario** (interpolación SQL). Reconsiderado vs typed-finders por-store; se mantiene `findWhere` genérico por extensibilidad, pero documentado como restricción de contrato.
- Implementar en los 4 stores reusando su mapper (segmento orderBy 'fecha_fin DESC', imagen 'capturada_at DESC', mensaje 'created_at DESC', position reconstruyendo batches desde `_tableBatches`).
- `imagen_repository_impl.dart:28-31` `getAllBySegmento`: `findAll()`+filtro Dart → `_offline.findWhere('segmento_id', segmentoId)`. BORRAR `getPendingBySegmento:33-38` (cero callers).
- `offline_repository.dart` (tras `findAll():51`): passthrough `findWhere`.
- `mensaje_local_store.findBySegmento` → wrapper delgado `=> findWhere('segmento_id', segmentoId)` (mantener orderBy 'created_at DESC'; no borrar, su caller es WS7).

**BLOQUE 2 — A2: renombrar `uploadPending` + borrar `UploadImageUseCase`.**
- `imagen_repository_impl.dart:45` `uploadPending(int)` → `uploadAllPending()`; reescribir docstring (drena TODAS las imágenes, no filtra por segmento). `[REVIEW G1]` **Coordinar con WS1.5:** tras cablear push, `uploadAllPending` SÍ tiene caller (ForzarEnvioController). El offline-guard de WS1 se mantiene.
- BORRAR `lib/domain/usecases/upload_image_usecase.dart`.

**BLOQUE 3 — A1: hoist de `_authHeader` + extracción unificada de remote-id.**
- `lib/data/sync/adapter_support.dart` (NEW, en `data/sync` NO en `core/sync` para no contaminar el motor extraíble):
  ```dart
  Future<Map<String,String>?> bearerAuthHeader(FlutterSecureStorage storage, {String key='auth_token'}) async { ... }
  int? extractRemoteIntId(Map<String,dynamic> payload, {List<String> keys=const ['id','remote_id','remoteId','itemId']}) { ... }
  int? parseRemoteId(String? remoteId) => remoteId==null ? null : int.tryParse(remoteId);
  ```
- imagen/mensaje/position adapters: reemplazar extracción inline por `extractRemoteIntId(data)?.toString()`. **Unifica la divergencia** (mensaje priorizaba `id`, position `remote_id`; ahora ambos `id` primero). `[REVIEW]` confirmar con backend la clave de `POST /positions/batch` (BE-7).
- `_authHeader()` en segmento/mensaje/position adapters + `segmento_remote_fetcher.dart` → `bearerAuthHeader(_storage)`. **El segmento adapter NO extrae remote-id del body** (devuelve `remoteId.toString()` del id que ya tenía) — solo cambiar su `_authHeader`. El interceptor HMAC de `NetworkService` firma cada request → el Bearer por-adapter es parcialmente redundante pero NO eliminar (riesgo auth), solo deduplicar.
- `markSynced`: extraer SOLO `parseRemoteId` (la conversión idéntica); NO unificar el `update(...)` completo (columnas divergen: `id` vs `remote_id`; campos extra: `needs_sync` en imagen) — forzar un método único introduciría un parámetro de discriminación que disfraza un caso especial (KISS).

**BLOQUE 4 — NF-25: sniff MIME robusto.** `imagen_remote_adapter.dart:64` `await file.openRead().first` toma el PRIMER CHUNK (no garantiza ≥4 bytes) → `_detectMime` cae a default `image/jpeg`. Reemplazar por `_readHeader(file, 12)` que acumula chunks de `file.openRead(0, 12)` hasta ≥12 bytes. Endurecer `_detectMime` con firmas binarias explícitas (JPEG FF D8 FF, PNG 89 50 4E 47, GIF, WebP RIFF...WEBP) + fallback por extensión + default. **`[REVIEW]` NO usar `package:mime`** (hace lookup solo por extensión, no por magic bytes → no resuelve NF-25, cuyo bug es que la extensión miente/falta).

**BLOQUE 5 — Código muerto.**
- `lib/initializer_controller.dart`: **NO borrar — WS0 ya lo borró** `[REVIEW: resuelve conflicto]`.
- `lib/domain/usecases/upload_image_usecase.dart`: borrado en Bloque 2.
- `lib/presentation/mapa/legacy/add_segmento_longpress_legacy.dart`: BORRAR (solo auto-referencias; nunca importado; se pudre).
- `SyncJobResult.pending`: **WS9 dropea su decisión 5d** `[REVIEW: resuelto por WS1]` — WS1 hace `result` nullable y elimina el valor del enum. WS9 no toca `sync_engine.dart`.

**Ficheros tocados:** `local_store.dart` (findWhere), `offline_repository.dart`, 4 stores, `imagen_repository_impl.dart` (rename), `adapter_support.dart` (NEW), imagen/mensaje/position/segmento adapters + fetcher, `upload_image_usecase.dart` (DELETE), `legacy/add_segmento_longpress_legacy.dart` (DELETE). **NO `sync_engine.dart`** (WS1), **NO `initializer_controller.dart`** (WS0).

**Tests nuevos:**
- `test/data/sync/{segmento,imagen,mensaje,position}_local_store_test.dart`: `findWhere` por columna devuelve filas correctas + orden; columna sin matches → `[]`; mensaje `findWhere('segmento_id',X) == findBySegmento(X)`.
- `test/data/sync/adapter_support_test.dart`: `extractRemoteIntId` prioriza 'id'; parsea String/num; null si ninguna; `bearerAuthHeader` null/header; `parseRemoteId('5')==5`, `('abc')==null`, `(null)==null`.
- `test/data/sync/imagen_remote_adapter_mime_test.dart`: JPEG/PNG/GIF/WebP por firma; fallback por extensión 'foto.png'; cabecera de 2 bytes no mal-etiqueta (`@visibleForTesting _detectMime`/`_readHeader`).

**Criterios de aceptación:** `flutter analyze` 0 nuevos; `grep` 0 de `getPendingBySegmento`/`UploadImageUseCase`/`InitializerController`/`LegacyAddSegmentoLongpressMixin`/`uploadPending(`; 4 stores implementan `findWhere`; `_authHeader` no existe en ningún adapter/fetcher; `extractRemoteIntId` única extracción en mensaje/position/imagen; sniff MIME acumula ≥N bytes + fallback; `getAllBySegmento` usa `findWhere`; ningún fichero de `lib/core/sync/` cambia semántica salvo +1 método en contract + 1 passthrough.

**Riesgos de regresión:** método abstracto en `LocalStore<T>` rompe compilación de stores sin implementar (solo 4) — implementar en el mismo commit. `findWhere` con interpolación = superficie de inyección (callers literales hoy; doc lo restringe). Unificar orden de claves cambia position (antes `remote_id` primero) — confirmar `POST /positions/batch` (BE-7). `getAllBySegmento` Dart→SQL WHERE: `segmento_id` es NOT NULL → equivalente. `mensaje.findBySegmento` wrapper debe mantener orderBy.

**Dependencia de backend:** ninguna para la limpieza. BE-7 (confirmar clave de id en respuestas) para que el orden unificado no capture mal.

**Decisiones abiertas:** `uploadAllPending` conservar → **sí** (entry-point de WS1.5/forzar-envío). Orden de claves → **`['id','remote_id','remoteId','itemId']`**. Hoist markSynced → **solo `parseRemoteId`** (KISS). MIME → **firmas a mano + fallback extensión** (no `package:mime`). Legacy mixin → **borrar** (la doc vive en git history). `adapter_support.dart` → **en `lib/data/sync/`** (depende de FlutterSecureStorage y forma de respuesta Enagas; no contaminar el motor genérico).

---

## 6. Orden de ejecución / PR breakdown

| # | PR | WS | Merge-blocker | Depende de |
|---|---|---|---|---|
| **PR-1** | Splash gate + connectivity un-hardcode + AppDI init único (`_initFuture`) + AppLog + DELETE InitializerController | WS0 (+NF-20) | **SÍ** | — |
| **PR-2** | Contrato `migrate`→DatabaseExecutor + migrateEntity atómico | WS8 (NF-19) | **SÍ** (base contrato) | PR-1 |
| **PR-3** | Outbox enqueue UPSERT (preserva remote_id) + AuthMiddleware + SessionState | WS8 (NF-21/22) | No | PR-1, PR-2 |
| **PR-4** | Bucle de drain acotado + hoist pipeline + quitar SyncJobResult.pending | WS1 | **SÍ** (prereq WS1.5) | PR-1 |
| **PR-4.5** | **Cablear push (forzar_envio + botón Subir en sync page)** `[REVIEW G1]` | **WS1.5** | **SÍ** | PR-4 |
| **PR-5** | Pull identity (ResolvedPullItem) + drop replace (upsert reconciliado) + syncing en detección + #5 opción-b | WS2 | **SÍ** (base WS4) | PR-2, PR-4 |
| **PR-6** | Pull desenlace tipado + pull_state degradado + sin éxito silencioso | WS4 | No | PR-5 |
| **PR-7** | Detalle local-only + preservación synced_at (mensaje/imagen) | WS3 | No | PR-5 |
| **PR-8** | Master-data sin tragar errores + cancel/cache + A3 shim | WS5 | No | PR-1, PR-6 |
| **PR-9** | GPS sin pérdida (mutex flush) + atribución + UTC + N+1 | WS6 | No | PR-2 |
| **PR-10** | Mensajes offline-first (cache fallback + dedup) | WS7 | No | PR-1 |
| **PR-11** | Limpieza: findWhere, adapter_support, MIME, código muerto | WS9 | No | **TODOS** |

**Espina serial:** PR-1 → PR-2 → PR-4 → PR-4.5 → PR-5. Tras PR-5, abanican PR-6/7/8/9/10.

**Ventanas paralelas:** PR-3 anytime tras PR-2 (disjunto de la espina). PR-9 tras PR-2 (solo firma migrate). PR-10 tras PR-1 (1 fichero, parallel-safe). PR-7 + PR-8 paralelos tras PR-5+PR-6 (3 lanes de fase D, sets disjuntos). PR-11 último.

---

## 7. Coordinación con backend (`docs/BACKEND_SYNC_CONTRACT.md`)

Ninguno bloquea merge cliente (todos con puente interino).

| # | Item | Desbloquea | Detalle |
|---|---|---|---|
| **BE-1** | `client_id` estable e idempotente en cada segmento del pull (`segmentos/bycts`) + echo en update | #2 (WS2) | Puente: WS2 resuelve por id numérico y reusa client_id local. |
| **BE-2** | Echo `client_id` en POST y GET mensajes + preservar `created_at` | NF-18 (WS7) | Puente: `_dedupKey` en cascada (id → fingerprint). Confirmar `created_at` a precisión ms. |
| **BE-3** | Idempotencia por `client_id` en TODOS los endpoints sync; duplicado → 200 con fila existente | NF-21 (WS8), #2, NF-18, WS1.5 | El cliente preserva remote_id/synced_at en re-enqueue (WS8); hace seguro el reintento de push (WS1.5). |
| **BE-4** | FKs entre entidades por `client_id` (esp. `imagen.segmento_client_id`) | A4 (fuera de alcance) | Puente WS3 NF-P: foto con `segmentoId = id ?? 0`; visualización local-only diferida. |
| **BE-5** | `updated_at` ISO8601 UTC en TODAS las entidades sync | A6 (WS6); conflict resolution | WS6 serializa GPS start/end en UTC (sufijo Z). |
| **BE-6** | `POST /positions/batch` idempotente por `batch_client_id` | WS6 durable | Sin cambio cliente más allá de UTC. |
| **BE-7** | Confirmar clave del id asignado en `POST /positions/batch` y `POST /operador/additem` (`id` vs `remote_id`) | A1 (WS9) | WS9 unifica orden `['id','remote_id','remoteId','itemId']`; cubre variantes actuales sin cambio backend. |
| **BE-8** | (Opcional) `error_message` español en 4xx + HTTP 409 con body completo del segmento en conflictos de update | #5 (WS2, opción b) | El cliente difirió SyncConflict-en-push; solo si el backend emite 409-con-body. |

---

## 8. Decisiones abiertas que requieren al humano (resolver ANTES de empezar)

| # | Decisión | Recomendación | Impacto |
|---|---|---|---|
| **D-1** | **WS0 O2:** introducir `AppLog` (facade sobre `logger`) ahora vs `debugPrint` interino | **AppLog ahora.** No-silent-failures exige stack; `debugPrint` se strippea en release. **WS5/WS6/WS7 dependen de esto** (WS7 G6: el `data is! List`→cache enmascararía regresión sin log real). | Bloquea PR-1; sin él WS7 traga con debugPrint. |
| ~~**D-2**~~ | **ANULADA (feedback).** No se añade UI. Los botones "Enviar"/"Enviar todos" y el aviso "Súbelos antes de descargar" ya existen. WS1.5 solo cablea los stubs. | — | Sin cambio de alcance UX. |
| **D-3** | **WS1.5:** ¿`drainAll()` en el engine o bucle de tipos en el controller? | **Bucle de tipos en el controller** (engine agnóstico de entidades; debe parar al primer `authExpired`). | Forma de PR-4.5. |
| ~~**D-4**~~ | **ANULADA (feedback):** no existe edición de metadatos de imagen en la app. NF-10 se reduce a **segmento** (editable+pulleable); imagen/mensaje son push-only/append-only, nunca re-upserteados por edición → sin cambio. | — | WS3 no toca synced_at de imagen/mensaje. |
| **D-5** | **WS6 (G4):** mutex `_flushing` — ¿aceptar que un flush descartado por mutex se reintenta en el siguiente tick (no se pierde, solo se difiere)? | **Sí.** El buffer queda intacto; el siguiente flush (timer 30s o threshold 500) lo envía. Sin pérdida. | Comportamiento de PR-9. |
| **D-6** | **Conflicto de spec confirmados (sign-off):** (1) AppDI init → `_initFuture` de WS8 en WS0; (2) `SyncJobResult.pending` → removido (WS1), WS9 dropea 5d; (3) upsert segmento → reconciliación de dos pasos (WS2); (4) DELETE InitializerController → solo WS0; (5) #5 → opción (b) sin tocar network_error. | **Aceptar las 5** (verificadas contra source en esta revisión). | Resuelve todas las colisiones HOT. |
| **D-7** | **WS3/WS6:** NF-10 en `position_local_store` — ¿incluir en WS3 (mixin) o WS6 (mismo fichero)? | **WS6** (mismo fichero que NF-23/NF-24, evita solapar PRs); aplica el mixin de WS3. | Asignación de fichero PR-7 vs PR-9. |

---

## 9. Estrategia de verificación

**Por cada PR:**
1. `dart format --set-exit-if-changed .` (CI gate del proyecto).
2. `flutter analyze --fatal-infos` → 0 issues nuevos; los lints `avoid_print` preexistentes NO aumentan (PR-1 los lleva a 0).
3. `flutter test` → verde, incluyendo los tests nuevos del PR.
4. El test de regresión del fix **falla en el commit anterior** y **pasa tras el fix** (verificar el rojo→verde explícitamente).

**Infra de test:** DB → `sqflite_common_ffi` in-memory (`sqfliteFfiInit()` + `databaseFactoryFfi`, patrón de `outbox_queue_test.dart`), recreando la tabla vía `store.migrate(db, 0, 1)`. Controllers/repos → `mocktail` con `Get.reset()` en `setUp`/`tearDown` y `registerFallbackValue` para tipos custom. Pipelines/acción → listener de prueba sobre el ActionManager para contar dispatches.

**Gates por fase:**
- **Fase A:** cold start sin crash (manual en dispositivo lento + splash test); `init()` idempotente; connectivity getter reactivo; migrateEntity atómico (test de rollback); AuthMiddleware redirige.
- **Fase B:** drain termina con N reintentables (timeout/fake_async); `isDraining==false` tras todo desenlace; **push funcional end-to-end** (encolar cambio → "Subir" → outbox drenado → `synced`).
- **Fase C:** repro de #2 arreglada (edit offline preservado en conflicto, sin StateError); fallo bloqueante de pull → `outcome==error` + `pull_state='error'` (no verde); fila degradada en la sync page.
- **Fase D:** master-data 500 → fila `error` sin avanzar timestamp; cache → `servedFromCache`; GPS sin pérdida bajo flush solapado (mutex); GPS UTC; detalle local-only persiste + foto persiste.
- **Fase E:** mensajes nunca `DataFailure` con store legible; dedup 1 copia sin client_id echo; `flutter analyze` 0 + grep de código muerto 0.

**Cobertura objetivo (skill flutter-testing):** controllers ≥90%, use cases/validators 100%, repos ≥80%, stores (los tocados) cobertura de los paths de fix al 100%.

**Cierre del plan:** tras PR-11, actualizar CLAUDE.md (nueva firma `migrate(DatabaseExecutor)`, regla "parse fallido → log + fallback determinista, nunca now()" en Lecciones aprendidas, eliminación de `UploadImageUseCase`/`InitializerController`/legacy mixin de la estructura, y el cableado de push en la sección de controladores de `ForzarEnvioController`).
