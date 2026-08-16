# CLAUDE.md — Helireport Enagas Webapp


---
## Skills

Las skills activas son las del plugin **`leulit-ia-tools`** (`/leulit-ia`), cargadas bajo
demanda: `leulit-ia-tools:flutter-core`, `flutter-testing`, `flutter-gis`, `flutter-offline-sync`,
`flutter-backend-integration`, `flutter-imaging`, `flutter-pdf-reports`, `flutter-forms-validation`,
`flutter-ci-cd`, `flutter-efficiency`, `engineering-principles`, más los agentes de review y los
comandos `/fix`, `/plan`, `/review`, `/logsdart`, `/parallel`.

Ya no hay skills locales en `.claude/skills/` — se eliminaron por duplicadas.

> **GetX es deuda técnica, no el objetivo.** El proyecto arrancó con GetX y todavía queda mucho
> (`GetxController`, `Get.toNamed`, `.obs`, bindings). No se puede cambiar de golpe: se elimina
> **poco a poco**, y el destino es exactamente lo que documentan las skills del plugin — MVVM
> sobre primitivas del SDK (`ChangeNotifier`, `ValueNotifier`/`ValueListenableBuilder`,
> `go_router`, `Command`/`Result`).
>
> Regla práctica:
> - **Código nuevo** → patrón del plugin. Nada de `.obs`/`Obx` nuevo; reactividad con
>   `ValueNotifier` + `ValueListenableBuilder`.
> - **Código que se toca** → migrar si el cambio ya lo abre; si no, dejarlo como está y no
>   ampliar la superficie GetX.
> - **Nunca** reescribir a GetX algo que ya salió de GetX.
> - Los singletons globales van en `DI` (get_it), no en el service-locator de GetX.
> - Toda migración de GetX que cambie funcionalidad o UX se valida con el responsable antes.

## Response Behaviour (Claude Code)

- **No preamble, no postamble** — start with code or the answer directly
- **Bug fixes**: one sentence cause + changed lines only
- **New feature with known pattern**: complete code, zero explanation
- **New pattern**: complete code + max 3 sentences rationale
- **Truncation is forbidden**: if showing a partial file, state explicitly which method changed
- **Multi-file changes**: list files first, then output each completely


## Non-Negotiable Code Standards

These apply to every line of code in this project, no exceptions:

### Architecture
- Clean Architecture: presentation → domain → data, no cross-layer leaks
- Un ViewModel/controller por pantalla o feature — nunca compartido. En pantallas ya migradas es un `ChangeNotifier`; en las que siguen en GetX, un `GetxController`. Lo global va en `DI`, no en un controller compartido.
- Repository interfaces in `domain/`, implementations in `data/`
- Use cases: one public method, one responsibility

### State Management
- **Destino: MVVM sobre primitivas del SDK** (`ChangeNotifier`/`ValueNotifier`, `go_router`, `Command`/`Result`) — ver skills del plugin. GetX es legacy en retirada (ver §Skills).
- Prohibido introducir stack nuevo: ni BLoC, ni Riverpod, ni Provider. Solo SDK.
- **DI de singletons globales: `leulit_flutter_dependency_injection` (`DI`/`di.get`, facade sobre get_it), NO el service-locator de GetX.** Servicios/stores/engine/repos-infra se registran y resuelven con `DI`. Regla: si es global → `DI.get<T>()`; si es controller de pantalla → binding GetX (mientras siga sin migrar). Lo que aún vive en GetX: routing (`GetMaterialApp`/`GetPage`/`GetMiddleware`), reactividad vieja (`.obs`/`Obx`) y bindings de controllers de pantalla.
- Vistas nuevas: `StatelessWidget` + `ListenableBuilder`/`ValueListenableBuilder`. `GetView<Controller>` solo en pantallas que aún no se han migrado.
- `StatefulWidget` only for: `AnimationController`, `FocusNode`, `WidgetsBindingObserver`
- Scope de rebuild lo más estrecho posible — `Obx` en lo viejo, `ValueListenableBuilder` en lo nuevo; envolver solo el widget que cambia
- Never put business logic inside `build()`

### Code Quality
- `const` constructors everywhere applicable
- Explicit types on all public APIs — no `var` on class members
- No `print()` — use logger with levels
- Error handling: always handle both branches of `Either<Failure, T>`
- No silent failures — every `catch` must log or propagate

### Performance
- `ListView.builder` / `SliverList` for any scrollable list
- `compute()` for any operation > ~16ms (image processing, JSON parsing, PDF generation), ask user if app needs to work in web browser
- `CancellableNetworkTileProvider` for all map tile layers
- Images: specify `cacheWidth`/`cacheHeight`, use `cached_network_image`


## Auto-mantenimiento de este fichero

**OBLIGATORIO:** Claude Code DEBE mantener este fichero actualizado automáticamente:

1. **Tras cada tarea completada**, revisa si los cambios afectan a la arquitectura, rutas, entidades, dependencias o patrones documentados aquí. Si es así, actualiza la sección correspondiente de este fichero.
2. **Al crear nuevos archivos**, añádelos a la sección de estructura si son módulos/vistas/servicios relevantes.
3. **Al modificar `pubspec.yaml`**, actualiza la versión y dependencias clave aquí.
4. **Al descubrir patrones o convenciones no documentadas**, añádelos a la sección correspondiente.
5. **Al corregir bugs recurrentes**, documenta la solución en la sección "Lecciones aprendidas".
6. **Al modificar rutas, roles, o entidades**, actualiza las tablas correspondientes.
7. **Usa la memoria persistente** (`~/.claude/projects/.../memory/`) para notas detalladas de debugging y enlaza desde aquí.
8. **El catálogo de referencia** (estructura de `lib/`, rutas, entidades, controladores, GetxServices, casos de uso, dependencias) vive en [`docs/ARCHITECTURE_REFERENCE.md`](docs/ARCHITECTURE_REFERENCE.md), NO aquí. Al crear archivos/entidades/rutas/servicios o cambiar `pubspec.yaml`, actualízalo **allí** con estas mismas reglas.

> Si detectas que alguna información aquí es incorrecta o está desactualizada, corrígela inmediatamente.

---

## Descripción del Proyecto

App móvil para operadores de campo — módulo **Desherbaje** de Enagas.
Permite gestionar actividades de desherbaje sobre segmentos de gasoducto: consultar el listado, cambiar estado, capturar fotos georeferenciadas (antes/después) y sincronizarlas con el backend cuando hay conectividad.

- **Versión:** `1.1.5+115`
- **SDK Flutter:** `>=3.27.0` | **SDK Dart:** `^3.12.1`
- **Backend:** `https://enagastool.helireport.com` (autenticación HMAC-SHA256)
- **Plataformas objetivo:** Android, iOS (no web actualmente)

---

## Catálogo de referencia (estructura, rutas, entidades, controladores, casos de uso, dependencias)

> El catálogo detallado vive en **[`docs/ARCHITECTURE_REFERENCE.md`](docs/ARCHITECTURE_REFERENCE.md)**: árbol completo de `lib/`, tabla de rutas, entidades de dominio con todos sus campos, controladores + GetxServices, casos de uso y dependencias de `pubspec.yaml` con versiones.
>
> Se mantiene fuera de este fichero para no inflarlo ni desincronizarlo: ese contenido refleja el código y se actualiza siguiendo las mismas reglas de auto-mantenimiento (ver arriba).

---

## Motor offline-first (Outbox + Pipeline)

> **Filosofía:** la UI siempre lee de SQLite local. La sincronización es **manual** y la dispara el usuario. Cuando hay red disponible, los cambios pendientes en el `OutboxQueue` se drenan al backend en cuanto el usuario lo pide. No hay timers ni reintentos automáticos.

### Componentes principales

```
TypeRegistry ←─ OfflineModule.registerEntity<T>(...) ←─ app_di.dart
       │
       ▼
LocalStore<T> ──┐
RemoteAdapter<T>?│        OfflineDatabase.open(path)
RemoteFetcher<T>?├─→ OutboxQueue ──→ SyncEngine.drain()       (push manual)
ConflictResolver<T>│                  PullCoordinator<T>.pullNow() (pull manual)
formatForDisplay? │
                └─→ OfflineRepository<T> ─→ create/update/delete (local + outbox)
```

### Flujo de escritura (push)

1. Controller de UI llama a `OfflineRepository<T>.update(entity)`.
2. Repo persiste en `LocalStore<T>` (transacción) **y** encola en `OutboxQueue`.
3. Repo dispatcha `SyncActions.entityQueued`. La UI escucha y refresca sus listas.
4. **Cuando el usuario pulsa "Subir"** (sync page o pantalla de entidad), `SyncEngine.drain()` recorre el outbox con un `TaskPipeline` por job: load entity → invoke adapter → interpret outcome → update local state → dispatch action.
5. Resumen final (`DrainSummary`): succeeded / retryable / rejected / conflicts.

### Flujo de lectura (pull)

1. Solo entidades con `RemoteFetcher` registrado son pulleables.
2. **Cuando el usuario pulsa "Descargar"** (o "Preparar trabajo de campo"), `PullCoordinator<T>.pullNow()` ejecuta un `TaskPipeline`: invoke fetcher → detect conflicts → upsert non-conflicting → enqueue conflicts → update pull_state → dispatch.
3. Conflicto = `localUpdatedAt > remoteUpdatedAt` OR outbox pendiente para ese `clientId`.
4. Cancelable cooperativamente vía `CancelToken`.

### Auth durante sync

`NetworkService` detecta 401 → `AuthExpiredException` → motor aborta drain/pull → dispatcha `SyncActions.authExpired` → `AuthExpirationHandler` limpia token y navega a login.

### Identidad universal

| Campo | Tipo | Regla |
|---|---|---|
| `clientId` | `String` (UUID v4) | Generado por el cliente al crear. **Inmutable**. PK lógica del dominio. |
| `remoteId` | `String?` | Asignado por el backend al primer sync. Nullable hasta entonces. |
| `updatedAt` | `DateTime` | Última edición local; conflict resolution. |

**Las FKs entre entidades en el dominio cliente viajan por `clientId`**, nunca por `remoteId`. El `RemoteAdapter` traduce a/de el formato del backend.

### Schema modular

Cada `LocalStore<T>` declara `entityType`, `schemaVersion`, y `migrate(DatabaseExecutor db, from, to)`. La tabla `_entity_schema_version` mantiene la versión por entidad (versionado independiente entre entidades, sin colisiones entre PRs). `OfflineDatabase.migrateEntity` ejecuta lectura de versión + `migrate` + escritura dentro de una **transacción** (atómico: una migración a medias hace rollback y no sube versión). La firma recibe `DatabaseExecutor` (no `Database`) para poder anidar en la transacción.

### Test de extensibilidad — añadir entidad nueva

```dart
// 1. La entidad implementa Syncable
class FooEntity implements Syncable { ... }

// 2. Local store con schema modular
class FooLocalStore extends LocalStore<FooEntity> {
  @override String get entityType => 'foo';
  @override int get schemaVersion => 1;
  @override Future<void> migrate(db, from, to) async {
    if (from == 0) await db.execute('CREATE TABLE foo (...)');
  }
  // ... CRUD ...
}

// 3. Adapter (push) y/o fetcher (pull)
class FooRemoteAdapter extends RemoteAdapter<FooEntity> { ... }

// 4. UNA llamada en app_di.dart
await OfflineModule.registerEntity<FooEntity>(
  entityType: 'foo',
  store: FooLocalStore(db),
  adapter: FooRemoteAdapter(network),
  conflictResolver: const ServerWinsResolver<FooEntity>(),
  fromJson: FooEntity.fromJson,
);
```

Ningún archivo del motor (`lib/core/sync/`) se modifica. Esto es la prueba de extensibilidad.

---

## Seguridad de Red

### Esquema HMAC único — TODA la API `/api/enagas/v1`
> A 2026-06-30 la app usa **un solo** esquema HMAC para todos los endpoints (login, segmentos, mensajes, imágenes, positions, tracks JSON y vídeo). El esquema legacy `x-flutter-*` + nonce fue eliminado: el backend nunca lo validó.

- **HMAC-SHA256 sin nonce**: `ApiSecurityService.buildHmacHeaders(method, path)` genera `X-HMAC-Signature` (hex lowercase) + `X-Timestamp` (**milisegundos**)
- Payload firmado: `"{timestampMs}:{METHOD_UPPERCASE}:{path}"`. `path` = relativo, sin host, con querystring si la hubiera. Ventana anti-replay ±5 min → firmar justo antes de enviar (también en cada reintento)
- **Sin Bearer token, sin nonce.** La firma HMAC es el único mecanismo de autenticación. El interceptor no añade `Authorization`; el `token` que devuelve el login se guarda en la entidad pero hoy no viaja como Bearer
- Dos instancias Dio, **mismo esquema**:
  - `NetworkService._dio` (REST general): `_HmacInterceptor` firma cada request — quita el host de `options.uri` y firma el path con prefijo `/api/enagas/v1`. Lleva `_RetryInterceptor` (5xx/408/429/timeout)
  - `NetworkService._videoDio` (solo vídeo): sin interceptors; cada método firma manualmente con `buildHmacHeaders`. Timeouts de 4 min (chunks grandes), sin retry (el adapter reintenta por chunk)
- Secret: `AppConfig.hmacSecret` vía `--dart-define=HMAC_SECRET=<64-hex>` (el backend lee `ENAGAS_HMAC_SECRET`). El placeholder por defecto NO valida → 401
- **401/403 = fallo de firma HMAC, NO expiración de sesión.** En rutas de vídeo → `SyncUnrecoverable`, sin logout. En login, `login_page_controller._parseError` mapea "401" a "Usuario o contraseña incorrectos"

---

## Convenciones de Código

- **Archivos:** `snake_case.dart`
- **Clases:** `PascalCase`
- **Variables/funciones:** `camelCase`
- **Patrón vista:** `nombre_page.dart` + `nombre_page_binding.dart` + `nombre_page_controller.dart`
- **DataGrid sources:** `nombre_datagrid_source.dart` (extiende DataGridSource de Syncfusion)
- **Barrel exports:** `export_core.dart`, `export_data.dart`, `export_domain.dart`, `export_views.dart` *(pendiente de crear)*
- **Linter:** `package:flutter_lints/flutter.yaml`
- **Idioma código:** Mezcla español/inglés. Nombres de entidades de negocio en español (actividad, segmento, desherbaje). Código técnico en inglés.
- **Assets:** imágenes en `assets/images/`

---

## Principios de Desarrollo

- **SOLID** con énfasis en SRP y DIP
- **KISS/DRY/YAGNI**: Soluciones simples, sin features especulativas
- **Performance**: Lazy loading, clustering de marcadores, Isolates para GIS pesado
- **Offline-first**: la UI siempre lee de SQLite local. Sync solo a petición del usuario (sync page o botones contextuales). Nunca timers ni reintentos automáticos.
- **Comunicación entre capas**: `TypedAction` (leulit_flutter_actionmanager). `.obs` solo widget↔controller.
- **Flujos secuenciales async**: `TaskPipeline<T>` (leulit_pipeline_pattern), nunca cadenas ad-hoc de awaits.
- **UX**: Minimizar clicks, feedback instantáneo, jerarquía visual clara
- **Platform-aware**: Comportamiento específico web/iOS/Android en marcadores, polilíneas, tooltips
- **Test de extensibilidad**: cada decisión arquitectónica debe permitir añadir una entidad nueva de forma mecánica sin tocar código existente.

---

## Lecciones Aprendidas

> Revisión + corrección del motor offline-first (rama `fixes/outbox-review`, 2026-06). Informe: `docs/CODE_REVIEW_REDESIGN_PATRON_OUTBOX.md`; plan: `docs/PLAN_FIXES_REDESIGN_PATRON_OUTBOX.md`.

- **Drain del outbox debe acotar el bucle.** Un `while(true)` que re-consulta `nextPending(status='pending')` se cuelga para siempre si un job reintentable vuelve a `pending` en la misma pasada. Usar un `Set<int>` de ids ya procesados y romper cuando el batch filtrado quede vacío. Resetear SIEMPRE `_isDraining` en `finally` (si no, queda en `true` y brickea todo drain futuro).
- **Identidad en pull, no re-acuñar `clientId`.** Si el backend omite `client_id`, `fromJson` genera un UUID nuevo cada pull → `findByClientId` no matchea → `upsert` con `ConflictAlgorithm.replace` BORRA la fila local editada por el índice UNIQUE de `id`. Resolver identidad por `findByRemoteId` reusando el `clientId` local; nunca `ConflictAlgorithm.replace` cuando hay índice único secundario (usar update-then-insert con `abort`).
- **Sin éxitos silenciosos.** Tareas `isBlocking=false` y `catch → debugPrint` reportan verde mientras los datos faltan. Todo desenlace (pull/master-data/GPS) debe ser representable (`PullOutcome { ok, okWithConflicts, partial, error, cancelled, authExpired }`) y propagado; los services de master-data deben relanzar, no tragar.
- **`AppDI.init()` se espera antes de la UI.** Fire-and-forget + `Get.find` en inicializador de campo → "X not found" en arranque. Gate con Splash que `await AppDI.init()`. `init()` es idempotente (`_initFuture ??= _init()`).
- **Parse fallido → log + fallback determinista, NUNCA `DateTime.now()`.** Un `updated_at`/timestamp corrupto no debe fabricar `now()` (rompe LWW/orden); loguear y caer a un valor determinista (p.ej. `endedAt`).
- **Buffers: escribir-luego-limpiar + mutex.** En flush de GPS, `await create()` PRIMERO y `removeRange` solo tras éxito; mutex `_flushing` no-reentrante (timer + threshold solapan). `clear()` antes del await pierde el lote si la escritura falla.
- **No tomar decisiones de funcionalidad/UX sin validación del responsable.** Distinguir corrección de bug (restaura intención) vs cambio de funcionalidad (requiere sign-off). Ver memoria `feedback_no_functionality_decisions`.
- **Doble esquema HMAC: aislar en el adaptador, no en el motor.** Cuando un endpoint usa un esquema de autenticación distinto al del resto de la app, la respuesta correcta no es modificar `NetworkService` para soportar modos, sino: (a) añadir un método estático nuevo en `ApiSecurityService` para el esquema nuevo; (b) añadir una instancia Dio separada en `NetworkService` con los timeouts y la ausencia de interceptors que requiere ese endpoint; (c) exponer 1-N métodos de facade en `NetworkService` que apliquen el esquema correcto manualmente. El motor (`sync_engine`, `outbox_queue`, etc.) y el motor de interceptors del Dio principal no se tocan.
- **401/403 no siempre es expiración de token.** `syncOutcomeFromNetworkError` asume que 401 = sesión expirada y lanza `AuthExpiredException`. Esto es correcto para endpoints con Bearer token. Para endpoints HMAC-only (vídeo), 401/403 = firma rechazada → `SyncUnrecoverable` sin logout. El adaptador debe bypassear el helper estándar con un `_mapNetworkError` propio que capture `NetworkErrorCategory.unauthorized` antes de llegar al helper.
- **DI: `DI` (get_it) y `Get` (GetX) son contenedores SEPARADOS — no mezclar.** `leulit_flutter_dependency_injection` es facade sobre get_it; registrar un global con `DI.register*` y leerlo con `Get.find<T>()` (o viceversa) lanza "not registered" en runtime aunque compile. Migrar uno sin el otro rompe producción Y tests. Además: **get_it NO dispara el lifecycle de `GetxService`** (`onInit`/`onClose`) — si un servicio movido a `DI` necesita su `onInit` (setup Dio, registrar listener), hay que llamarlo manualmente en el factory de registro. Tests: registrar globales con `DI.registerSingleton` + `await DI.reset()` en setUp/tearDown; controllers de pantalla siguen con `Get.put`/`Get.reset`. Ver memoria `feedback_di_getit_vs_getx_separate`.
- **El grafo codebase-memory es ciego a la DI de GetX/get_it (resolución runtime por tipo).** `trace_path` da falsos "cero callers" para servicios. Para dead-code de servicios: `grep Get.find / DI.get`, no el grafo. Ver memoria `feedback_graph_blind_to_getx_di`.
- **El esquema de firma migra JUNTO con el path, no solo la URL.** Mover endpoints a un prefijo nuevo (`/api/enagas/v1`) sin migrar el firmador HMAC del Dio principal = 401 en todo. Síntoma engañoso: "Usuario o contraseña incorrectos" (el controller mapea cualquier "401" a credenciales). El backend valida UN esquema; el interceptor del Dio principal debe usar exactamente ese, no uno legacy paralelo. Lección derivada: cuando coexisten dos firmadores y el backend solo acepta uno, no "aislar el nuevo en su adaptador" — **unificar** y borrar el legacy (es un footgun que revive el 401). Verificado con backend en `flutter-security.js` / `usuarios.routes.js`.
- **Capas de marcadores masivas: clustering + culling, nunca `MarkerLayer` crudo.** Una capa clonada hereda el techo de rendimiento del original: `PksMapLayer` (13k puntos) salía por los pelos, y su clon para hitos (48k) dejó de pintarse — el frame no se completa y parece "no se cargan los datos". Toda capa de puntos va sobre `ClusteredMarkerLayer<T>` (`SuperclusterImmutable` + `search` por `visibleBounds` en cada cambio de cámara). Y ante "no se ve", medir el estado en runtime (VM Service / DTD) antes de sospechar de la descarga: ahí el dato ya estaba en SQLite. Ojo también con `Marker.alignment`: `topCenter` deja el widget ENCIMA del punto (pico de la etiqueta sobre la coordenada); `bottomCenter` lo baja y desplaza el pico.
- **`POST` con `Content-Type: application/json` y cuerpo vacío = 400 `FST_ERR_CTP_EMPTY_JSON_BODY` en Fastify.** No es opcional: si el endpoint no necesita cuerpo (el id viaja en el path, como `sync-complete` o `videos/upload/{id}/complete`), hay que mandar `{}` igualmente. `NetworkService.post` fija el content-type SIEMPRE, así que un `body` nulo produce un rechazo determinista en cada intento. Ojo al enmascaramiento: un endpoint idempotente puede ocultar el fallo cuando el trabajo ya estaba hecho (el adapter de vídeo salía por `getVideoStatus → complete == true` sin llegar a llamar al `complete` roto), así que "ahora funciona" no prueba que el POST esté bien. (Fix 2026-07-20.)
- **`rejected` es un estado terminal que bloquea envío Y purga a la vez: sin una vía explícita de vuelta a `pending`, el sobre queda tapiado para siempre.** `nextPending` lee solo `status='pending'`, así que el drain nunca reprocesa un `rejected`; pero `readUnsyncedSets` sí lo cuenta, así que la purga tampoco cierra. Si además el padre no tiene job que entregar (`succeeded == 0`), el reencolado del sobre —condicionado a `succeeded > 0`— no dispara: cerrojo permanente y pérdida silenciosa de media de campo. Regla: todo estado terminal necesita una acción de usuario que lo revierta, acotada al sobre (filtro por `clientId`, jamás jobs de otros segmentos) y conservando la `operation` original del job. Y todo guarda de "no reenviar lo ya subido" debe enumerar en qué estados deja de proteger y pasa a bloquear. (Fix 2026-07-20.)
- **Un rechazo cuyo motivo no se propaga es un fallo silencioso.** `_mapDioException` solo rescataba `data['message']` cuando era `String`: cualquier otra forma de cuerpo caía al texto genérico de Dio y el `last_error` del outbox no decía nada. Al mapear un error HTTP, adjuntar siempre el cuerpo (serializado y recortado) cuando no haya mensaje legible. Y en la UI: `DrainSummary` solo cuenta; el motivo viaja en `SyncActions.entityRejected` — si nadie lo escucha, el operador ve un botón que "no hace nada".
- **El wire lo define el adaptador, no la entidad: añadir un campo a `toJson` NO es enviarlo.** Los adaptadores de push de media montan su payload campo a campo (`fields` del multipart en foto, body del init en vídeo) y nunca llaman a `toJson`, así que `gis_json` se generó, persistió y pintó en el mapa durante días sin salir del móvil — con la doc del contrato diciendo que sí viajaba. Al añadir un campo sincronizable, el test que vale es el que captura el payload REAL del adaptador; un test sobre `toJson` deja pasar el bug entero. Y un campo opcional se omite (clave ausente), nunca `''` ni `"null"`: el backend los guardaría como valor válido. (Fix 2026-07-21.)
- **FKs de entidades hijas locales van por `clientId` (id local), nunca por el id remoto nullable.** Enlazar fotos/vídeos al segmento por `segmento_id` (id de nube) rompe en campo: el id remoto es `null`/`0` hasta que el segmento sube, así que las capturas caen todas bajo `0` (colisión entre segmentos) y no se reencuentran al recrear la vista — la media parece "perderse" aunque está en SQLite. Regla: la FK cliente→cliente viaja por la identidad que SIEMPRE existe (`clientId`); el id remoto es solo para el push. Y ningún reload debe hacer early-return por `id == null` — leer siempre del store local por `clientId`. (Fix 2026-07-09: columna `segmento_client_id` en `imagenes_segmento`/`videos_segmento`.)
- **Un `TileLayer` sin `fallbackUrl` es un single point of failure, no un límite de zoom.** Si el único proveedor de tiles no tiene cobertura a ese nivel de zoom en esa zona, el mapa sale en blanco AL ENTRAR a la pantalla — y el síntoma ("blanco al abrir, bien al alejar el zoom") se lee como bug de límite de zoom cuando en realidad es que no hay red de respaldo si el proveedor falla o no cubre. Declarar siempre `fallbackUrl` en todo `TileLayer`. Y `maxNativeZoom` en flutter_map 8.x tiene default 19 — si el proveedor sirve hasta 20 (u otro nivel) y no se declara explícitamente, ese último escalón sale reescalado (borroso) en vez de servido nativo. (Fix 2026-07-22: los tres `TileLayer` del módulo, ver ARCHITECTURE_REFERENCE.md.)
- **El `TextEditingController` de un diálogo lo posee el widget, nunca la función que lo abre.** Crear el controller en la función `showXDialog()` y hacer `dispose()` en su `finally` lo mata en cuanto resuelve el future de `Get.dialog` — pero la ruta sigue animando la salida (~150-250 ms) y su `TextField` se reconstruye durante esos frames: `A TextEditingController was used after being disposed`. El subárbol queda roto y arrastra una cascada que no se parece a la causa: `AnimatedDefaultTextStyle` (el label de `InputDecoration`) marcado dirty y huérfano → `Tried to build dirty widget in the wrong build scope`; `getTransformTo` sobre render objects sueltos → `object.dart: 'attached': is not true`; y al reiniciar, `Duplicate GlobalKeys` de `_OverlayEntryWidgetState` con el `_Theater` DETACHED. Regla: el controller vive en un `StatefulWidget` privado del diálogo y se libera en su `dispose()` — el framework lo hace cuando la ruta ya no existe. (Fix 2026-07-23: `finalize_traza_dialog.dart` y `lines_cut_dialog.dart`.) Un `TextEditingController` propiedad de un `GetxController` y liberado en su `onClose()` —`segmento_detalle_controller.dart`— es correcto y no entra en esta regla: el dueño sobrevive al diálogo.
- **Un wipe borra FILAS, no ESQUEMA: `_entity_schema_version` queda fuera.** `OfflineDatabase.wipeAll` enumeraba tablas de `sqlite_master` y vaciaba también la de versiones. Las tablas seguían existiendo con sus columnas, pero cada entidad volvía a versión 0, así que en el arranque siguiente `migrate(0, N)` reejecutaba el DDL completo y el primer `ALTER TABLE … ADD COLUMN` moría con `duplicate column name` — app inarrancable tras pulsar "Reset". Regla: todo borrado masivo enumera qué tablas de infraestructura NO toca y por qué. Y ojo con el reflejo de "vaciar todo": el estado que describe el esquema no es dato de usuario. (Fix 2026-07-23.)
- **Estado de UI persistido fuera de SQLite = estado que el reset olvida.** Las fechas de "última descarga" de la página de sincronización viven en `SharedPreferences` (`sync_master_last_download_*`), no en la BD, así que `wipeAll` las dejaba intactas y tras el reset cada fila seguía anunciando una descarga que ya no existía en local. Al añadir un botón de borrado, la lista de lo que borra se hace por almacén (SQLite + prefs + ficheros), no por tabla. (Fix 2026-07-23.)
- **Un botón "Cancelar" que tarda minutos en reaccionar es un botón roto.** La cancelación cooperativa hay que llevarla hasta el bucle largo REAL, no solo al bucle exterior. En el push, el bucle largo no es el del outbox (un job por foto/mensaje) sino el de chunks del `VideoRemoteAdapter` (5 MB por vuelta, ~60 vueltas en un vídeo de 300 MB): comprobar el token solo entre jobs deja al operador pulsando un botón que no responde. Por eso `CancelToken` viaja en el contrato `RemoteAdapter.push` y llega al `SyncJobContext`. Corolarios: (a) el job en vuelo vuelve a `pending` (`SyncCancelledException` → `markPendingAgain`), NUNCA se queda en `syncing` — `nextPending` no lo vería hasta reiniciar la app; (b) `cancelled` es un desenlace propio en `DrainSummary`, no un `retryable` más, porque "lo paré yo" y "falló la red" exigen mensajes distintos; (c) hace falta un tercer estado de UI ("Cancelando…"): si el botón vuelve a "Enviar" al instante, la pantalla dice "listo" mientras aún salen bytes y un segundo toque solaparía envíos; (d) ocultar los botones de navegación no basta — sin `PopScope(canPop:false)` el back del sistema destruye la ruta con el envío vivo. (2026-07-23.)
- **Si el spinner vivía dentro del botón, convertir ese botón en "Cancelar" borra el único indicio de actividad.** Al añadir un estado nuevo a un control hay que mirar qué señal ocupaba ese hueco antes. El feedback se movió a una barra propia (`_ProgresoEnvioBar`): `LinearProgressIndicator` + texto. Y el progreso tiene DOS escalas que no se sustituyen entre sí — "elemento N de M" (lo sabe el llamante, basta un contador) y bytes dentro de un elemento (solo lo sabe el adaptador). El vídeo dura minutos bajo UN job, así que sin la segunda el contador se queda quieto y parece colgado: `SyncProgressCallback` viaja por el mismo camino que `CancelToken` (contrato `RemoteAdapter.push` → `SyncJobContext` → `drain`) y la barra pasa de indeterminada a determinada solo mientras hay bytes. Detalles que se olvidan: emitir el offset INICIAL (en una reanudación la barra debe arrancar donde está, no en 0 %) y poner la fracción a `null` al acabar cada drain (si no, se queda clavada al 100 % del vídeo anterior mientras suben las fotos). (2026-07-23.)

- **Una consulta de "recuperación de crash" que solo mira `ended_at IS NULL` no distingue lo abandonado de lo VIVO.** La traza que se está grabando ahora mismo cumple exactamente el mismo predicado que la que dejó un crash, así que `_recoverOrphanedTraza` (segmentos_list) disparaba el diálogo no descartable de "finalizar registro" al entrar en la pantalla con el GPS en marcha. El diálogo era el síntoma bonito; el daño real es que `finalizeOpen` cierra la fila y encola el job mientras el servicio sigue grabando: los puntos siguientes caen en una traza ya finalizada y el `finish()` posterior encola un SEGUNDO job para el mismo `clientId`. El guard va en el servicio (`openTrazaFor` devuelve `null` si `isRecording`), no en la pantalla: la invariante "lo que estoy grabando no es huérfano" es del dueño del estado, y así cualquier futuro llamador la hereda. Nada se pierde: una huérfana real se recupera al volver a entrar tras pulsar Stop, cuando vuelve a ser la única abierta (importa porque `findOpen` usa `limit 1` sin `orderBy`, y con dos filas abiertas devolvía una arbitraria — alcanzable porque login puede aterrizar en `sincronizacion`, no siempre en `segmentos`). (Fix 2026-07-23.)

- **Un widget de capa reconstruido por frame anula las cachés internas de flutter_map.** `MarkerLayer` y `PolylineLayer` cachean la proyección (trigonometría por punto) y la simplificación Douglas-Peucker, pero `didUpdateWidget` las invalida ante **cualquier instancia nueva** — incondicionalmente, sin comparar contenidos (`marker_layer.dart:58-65`, `layer_projection_simplification/state.dart:52-59`). Como `MapCamera.of(context)` notifica en cada frame de gesto, una capa que construya `MarkerLayer(...)`/`PolylineLayer(polylines: x.toList())` en su `build` re-proyecta TODO en cada frame, y el `.toList()` dentro de un `Obx` produce lista nueva aunque los datos no hayan cambiado. La respuesta no es dejar de repintar: es **devolver la misma instancia de widget** mientras el resultado no cambie — memo por bounds acolchados (~35%) + zoom entero en `ClusteredMarkerLayer`, widget cacheado y sustituido solo vía `ever` en `GasoductosMapLayer`. El culling fino lo sigue haciendo la capa cada frame, así que no cambia lo que se pinta. (2026-07-28.)
- **El índice espacial no debe cubrir zooms que nunca se consultan.** `SuperclusterImmutable` construye un KD-tree por nivel entre `minZoom` y `maxZoom+1`: con `minZoom: 1, maxZoom: 20` son 21 árboles síncronos en el hilo de UI, ×3 capas. Pero la capa corta con `SizedBox.shrink()` por debajo de su propio `minZoom` (14, o 12 en posiciones fijas), así que los niveles bajos se construyen y nunca se buscan. Regla: `minZoom` del índice = `minZoom` de la capa − 1 (colchón de un nivel por el borde `floor`/`ceil`). `_limitZoom` clampa hacia el `minZoom` del índice sin lanzar, así que pasarse por arriba devuelve silenciosamente el nivel de agregación equivocado — por eso el margen va hacia abajo. (2026-07-28.)
- **`fallbackUrl` en un `TileLayer` desactiva el `ImageCache` de Flutter.** `NetworkTileImageProvider.operator ==` devuelve `false` siempre que `fallbackUrl != null`, así que la caché en memoria nunca acierta y cada tile que reaparece al panear se redecodifica; además, si se usa el fallback, ese tile tampoco se guarda en la caché de disco. Para conservar la resistencia a huecos de cobertura (la lección del 2026-07-22) SIN pagar eso: **dos `TileLayer` apilados**, respaldo debajo con `maxNativeZoom` bajo (~15, pide 1 tile por cada 32×32 del nivel alto) y el principal encima, ninguno con `fallbackUrl`. Cuesta 1× de overdraw, que es más barato que redecodificar. Vive en `lib/core/widgets/orto_tile_layers.dart`, compartido por los 3 mapas. (2026-07-28.)
- **Un plugin "estándar" puede ser justo el motivo de que falte la feature.** `flutter_map_cancellable_tile_provider` estaba en los estándares del proyecto, pero su README lo declara **deprecado desde flutter_map 8.2**: el `NetworkTileProvider` nativo absorbió la cancelación Y añadió caché de tiles en disco. Al ser un paquete anterior a 8.2, usarlo era exactamente la razón de que la app no tuviera caché de tiles. Antes de escribir un `TileProvider` propio (o de meter FMTC), leer el CHANGELOG de la versión instalada. Detalle que no es cosmético: `BuiltInMapCachingProvider` sin `overrideFreshAge` manda un `If-Modified-Since` cuando el tile está rancio y, sin red, cae a tile transparente — con 365 días se sirve de disco y el offline funciona. Y `destroy()` dispara `resetSingleton`: hay que **reconfigurar justo después** o la app se queda con los defaults hasta el siguiente arranque en frío. (2026-07-28.)
- **`compute()` con un objeto ya decodificado paga una copia profunda en el hilo emisor.** Mover el parseo de un GeoJSON de 48k features a un isolate no sirve de nada si lo que se envía es el `Map` que Dio ya decodificó en el hilo de UI: el decode sigue donde estaba y encima se añade un recorrido O(n) para serializar el grafo al cruzar. Hay que mandar el **`String` crudo** (`ResponseType.plain` en la petición) y hacer `jsonDecode` + mapeo dentro del isolate; que vuelvan records planos de primitivas y se construyan los `LatLng`/entidades fuera. Corolario de alcance: PKs e hitos ya cortan antes de red (`if (!_conn.isConnected) → _loadFromCache`), así que esto arregla la primera carga y el botón Refrescar, NO el arranque diario — ese son 48k filas de sqflite cruzando el method channel, que no se mueve a un isolate sin cambiar de motor de BD. (2026-07-28.)
- **Filtrar `MapEvent` por `event.source` para detectar movimientos programáticos es una trampa.** Parece la forma limpia de cubrir `zoomIn`/`zoomOut`/`fitCamera`, que no emiten eventos `*End`, pero `flutter_map_location_marker` mueve y **rota la cámara con `MapEventSource.mapController` en cada lectura de brújula** (`current_location_layer.dart:783`) cuando `alignDirectionOnUpdate: AlignOnUpdate.always`: decenas de eventos por segundo justo en el modo más activo. El que mueve la cámara a propósito ya sabe que lo ha hecho — que llame él a lo que haga falta, en vez de inferirlo del evento. `_isViewSettleEvent` se queda solo con los `*End` reales. (2026-07-28.)
- **Un filtro que responde a la pregunta equivocada tapia datos en el móvil.** "Forzar envío" listaba por estado (`{finalizada, contratista}`), pero la pregunta que tiene que contestar esa pantalla es "¿tengo bytes sin subir?", que es otra dimensión y la contesta el outbox. Con el filtro por estado, un mensaje escrito a un segmento en `ejecución` no había forma de enviarlo: no aparecía. Y quitar el filtro solo no basta — hay que mirar qué invariantes se apoyaban en él. Aquí eran dos: (a) el rescate del sobre "subido pero sin el 200 de `sync-complete`" iba por `s.id != null`, que sin el recorte por estado es cierto para todo lo descargado; (b) el reencolado del sobre entero tras un `upsert` entregado era correcto SOLO porque el único envío posible ocurría con el sobre nunca cerrado. La primera se sustituye por dato persistido (`segmentos.sync_confirmed_at`, epoch ms del último cierre confirmado); la segunda, por el mismo dato: se reenvía únicamente lo entregado DESPUÉS de esa frontera, que es exactamente lo que el backend tiene en `estadotransmision='pending'` y que `cleanupPendingChildren` borrará. Reenviar de más duplica media en nube (la API no deduplica por `client_id`); de menos, la pierde. La frontera se graba con `max(synced_at)` de los jobs del sobre y NO con `now()`: así los dos lados de la comparación salen de `OutboxQueue.markSynced` y un salto del reloj del dispositivo no puede dejar jobs cerrados al otro lado. (2026-07-28.)
- **`sync-complete` no es "el último paso del último envío": es lo que blinda lo ya subido.** Marca segmento e hijos como `complete` en backend, y solo lo `complete` sobrevive al `cleanupPendingChildren` del siguiente `upsert`. Por eso hay que llamarlo en CADA envío que deje el sobre limpio, no solo al finalizar la actividad — y por eso cerrar en nube y borrar en local son decisiones separadas: se cierra siempre, se purga solo con `estado ∈ {finalizada, contratista}`. Purgar un `ejecución` lo borraría del móvil para siempre, porque `GET /segmentos/contratista` solo sirve `propuesta` y `validada`. Corolario en backend: `markSyncCompleted` filtra por `sync_completed_at IS NULL`, así que reabrir el ciclo (`partialUpdate` con `pending`) tiene que limpiar esa marca o del 2º envío en adelante el segmento se queda `pending` para siempre. Un flag que solo funciona la primera vez es un flag roto en cuanto el reenvío deja de ser la excepción. (2026-07-28.)
- **`static final _x = Get.find<T>()` en un widget es una referencia colgada, no una optimización.** Un `static final` se resuelve una vez y no se reevalúa nunca, pero un controller de pantalla registrado con `Get.lazyPut` muere al salir de la ruta: al volver a entrar, el campo sigue apuntando al viejo y se acaba montando un `ValueListenableBuilder` sobre un `ValueNotifier` disposed. Si molesta el `Get.find` en `build`, la vía correcta es resolverlo en el `initState` de un `StatefulWidget` (el `State` muere con la ruta). Aunque normalmente ni eso: `Get.find` es una búsqueda en un mapa por tipo, no se mide al lado de cualquier trabajo de capa. (2026-07-28.)

---

## Pendiente / TODO

### Backend (entregable en `docs/BACKEND_SYNC_CONTRACT.md`)
- Recuperar contraseña por **código OTP** — flujo completo dentro de la app (`ResetPasswordPage`). La app ya llama a `POST /users/recuperar-password` (pide código) y `POST /users/restablecer-password` (código + nueva contraseña); faltan ambos en el backend (spec: `docs/BACKEND_RECUPERAR_PASSWORD.md`).
- Idempotencia por `client_id` en TODOS los endpoints sincronizables.
- FKs entre entidades por `client_id` (no `remote_id`).
- `error_message` legible en español en respuestas 4xx (especialmente 422).
- `GET /mensajes?operador=X` para pull global de mensajes (§12.1) — hasta entonces lectura online + merge con pendientes locales.
- `GET /api/gasoductos` y `GET /api/pks` REST únicos para integrar master data al motor (§12.2) — hasta entonces flujo legacy multi-archivo GeoJSON.
- `POST /trazas` idempotente por `traza_client_id` (payload: `FeatureCollection`/`MultiLineString`, no batches de puntos sueltos) para subida de trazas GPS. Tamaño no es problema: techo de 1 punto/s (`distanceFilter` 5 m + `intervalDuration` 1 s) × 2 h de grabación máxima ≈ 360 KB, dentro del default de Fastify.
- `updated_at` ISO8601 UTC en TODAS las entidades sincronizables.

### Plataforma — al publicar (config nativa ya cableada en repo)
- Android: minSdk **34**, manifest declara `FOREGROUND_SERVICE_LOCATION` y el `<service>` del plugin con `foregroundServiceType="location"`.
- iOS: deployment target **13.0**, `Info.plist` lleva `UIBackgroundModes=[location, fetch, processing]` + las tres descripciones `NSLocation…UsageDescription`.
- Justificaciones Play Console / App Store para `FOREGROUND_SERVICE_LOCATION` y modos de fondo iOS al primer release (trámite estándar para tracking apps).

### Cliente
- Reescribir `GasoductosService` y `PksService` al motor cuando backend tenga endpoints REST (ver §12.2 doc backend).
- Migrar lectura de `MensajeSegmento` al motor cuando backend exponga endpoint de pull global (§12.1).
- **Decidir `simplificationTolerance` de las polilíneas.** Hoy se usa el default de flutter_map (0.3 px). Subirlo a 0.5-1.0 abarata el pintado de gasoductos en cada frame, pero altera la fidelidad del trazado: es una decisión visual, requiere comparativa en pantalla y sign-off del responsable.
- **Medir en dispositivo el efecto de la pasada de rendimiento del mapa (2026-07-28).** Timeline de DevTools (hilos UI y raster) paneando a zoom 15-18 con hitos y PKs visibles. La optimización se hizo por auditoría estática, sin baseline medido.
- Filtro de solapamientos del corte contra segmentos existentes (`docs/LINES_CUT_MOBILE_INTEGRATION.md` §8).
- `AppConfig.hmacSecret` ya se inyecta por `--dart-define=HMAC_SECRET` (default = placeholder que NO valida). Pendiente: cablearlo en CI/CD desde un GitHub Secret y documentar en `.vscode/launch.json` para desarrollo local.
- Extraer `lib/core/sync/` a paquete `leulit_offline_sync` cuando madure.
- **Vídeos de nube — verificar auth de streaming en runtime** *(2026-07-09: ya se muestran y reproducen)*: la media de nube (fotos + vídeos) se pinta en Antes/Después vía `segmento.imagenes[]` (un vídeo es una fila con `mime_type` `video/*`); `VideoPlayerPage.network` reproduce por URL. **Pendiente:** confirmar en dispositivo real que la `url` de vídeo se sirve sin HMAC (como las imágenes); si da 401, firmar/proxy el streaming.
- **Dedup media local↔nube exige eco de `client_id` en backend**: sin él, una foto/vídeo subido reaparece duplicado tras el pull (agravado en vídeo por el remux mov→mp4 que cambia el filename). Parte del contrato pendiente "idempotencia por client_id".
- **Vídeos — confirmar idempotencia re-Init con `client_id`**: spec dice que re-init con mismo `client_id` reutiliza sesión en curso; verificar comportamiento real del backend ante re-init de sesión ya completada.
