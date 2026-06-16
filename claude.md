# CLAUDE.md — Helireport Enagas Webapp


---
## Skills

### Core Skills (Activated)
@.claude/skills/flutter-core/SKILL.md
@.claude/skills/flutter-efficiency/SKILL.md
@.claude/skills/flutter-ci-cd/SKILL.md
@.claude/skills/flutter-imaging/SKILL.md
@.claude/skills/flutter-gis/SKILL.md
@.claude/skills/flutter-ci-cd/SKILL.md
@.claude/skills/flutter-testing/SKILL.md
@.claude/skills/flutter-pdf-reports/SKILL.md
@.claude/skills/flutter-offline-sync/SKILL.md
@.claude/skills/flutter-forms-validation/SKILL.md
@.claude/skills/flutter-backend-integration/SKILL.md
@.claude/skills/grill-me/SKILL.md

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
- One `GetxController` per screen/feature — no shared controllers unless it's a `GetxService`
- Repository interfaces in `domain/`, implementations in `data/`
- Use cases: one public method, one responsibility

### State Management
- GetX only — no BLoC, no Riverpod, no Provider
- `StatelessWidget` + `GetView<Controller>` as the default
- `StatefulWidget` only for: `AnimationController`, `FocusNode`, `WidgetsBindingObserver`
- `Obx` scope as narrow as possible — wrap only the rebuilding widget
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

> Si detectas que alguna información aquí es incorrecta o está desactualizada, corrígela inmediatamente.

---

## Descripción del Proyecto

App móvil para operadores de campo — módulo **Desherbaje** de Enagas.
Permite gestionar actividades de desherbaje sobre segmentos de gasoducto: consultar el listado, cambiar estado, capturar fotos georeferenciadas (antes/después) y sincronizarlas con el backend cuando hay conectividad.

- **Versión:** `1.0.0+1`
- **SDK Flutter:** `>=3.11.0` | **SDK Dart:** `>=3.3.0 <4.0.0`
- **Backend:** `https://enagastool.helireport.com` (autenticación HMAC-SHA256)
- **Plataformas objetivo:** Android, iOS (no web actualmente)

---

## Estructura de lib/

```
lib/
├── main.dart                                      # Entry point, inicialización GetX services
├── main_app.dart                                  # GetMaterialApp config, tema, rutas
├── core/
│   ├── app_config.dart                            # baseUrl, hmacSecret
│   ├── app_di.dart                                # DI global. Registry → DB → engine → entities
│   ├── app_router.dart                            # AppRoutes + AppPages + AuthMiddleware
│   ├── app_theme.dart                             # Colores, TextStyles, espaciado
│   ├── app_typed_actions.dart                     # TypedActions globales del proyecto
│   ├── api_endpoints.dart                         # URLs externas y endpoints del backend
│   ├── my_getx_controller.dart                    # Base controller con TypedAction lifecycle
│   ├── result/data_result.dart                    # Either<Failure, T> del proyecto
│   ├── services/
│   │   ├── api_security_service.dart              # Generación headers HMAC
│   │   ├── auth_expiration_handler.dart           # Listener global de SyncActions.authExpired
│   │   ├── connectivity_service.dart              # GetxService: monitoriza red
│   │   ├── gasoductos_service.dart                # Master data legacy (no integrado al motor)
│   │   ├── gps_background_service.dart            # GPS background con buffer 500/30s
│   │   ├── gps_service.dart                       # Permisos de ubicación
│   │   └── pks_service.dart                       # Master data PK legacy
│   └── sync/                                      # Motor offline-first (extraíble a paquete)
│       ├── sync.dart                              # Barrel export público
│       ├── sync_actions.dart                      # TypedActions del motor
│       ├── type_registry.dart                     # TypeRegistration<T> + TypeRegistry
│       ├── offline_module.dart                    # registerEntity<T>() — extension point
│       ├── contracts/
│       │   ├── syncable.dart                      # clientId/remoteId/updatedAt/toJson
│       │   ├── local_store.dart                   # entityType + schemaVersion + migrate + CRUD
│       │   ├── remote_adapter.dart                # push() + SyncOutcome variants
│       │   ├── remote_fetcher.dart                # pullAll() (opcional por entidad)
│       │   ├── conflict_resolver.dart             # 4 presets: ServerWins/LocalWins/LWW/Interactive
│       │   ├── sync_job.dart                      # SyncOperation + SyncStatus + SyncJob row
│       │   └── auth_expired_exception.dart        # Excepción 401 que aborta drain
│       ├── database/
│       │   └── offline_database.dart              # WAL + tablas infra + migrateEntity
│       ├── outbox/
│       │   └── outbox_queue.dart                  # CRUD sync_queue (sin retry, sin backoff)
│       ├── engine/
│       │   ├── sync_engine.dart                   # drain() con TaskPipeline por job
│       │   ├── sync_job_context.dart
│       │   └── tasks/
│       │       ├── load_entity_task.dart
│       │       ├── invoke_remote_adapter_task.dart
│       │       ├── interpret_outcome_task.dart
│       │       ├── update_local_state_task.dart
│       │       └── dispatch_action_task.dart
│       ├── pull/
│       │   ├── cancel_token.dart                  # Cancelación cooperativa
│       │   ├── pull_context.dart
│       │   ├── pull_coordinator.dart              # pullNow() con TaskPipeline
│       │   └── tasks/
│       │       ├── invoke_remote_fetcher_task.dart
│       │       ├── detect_conflicts_task.dart
│       │       ├── upsert_non_conflicting_task.dart
│       │       ├── enqueue_conflicts_task.dart
│       │       ├── update_pull_state_task.dart
│       │       └── dispatch_pull_completed_task.dart
│       └── repository/
│           └── offline_repository.dart            # CRUD genérico local + outbox enqueue
├── domain/
│   ├── entities/
│   │   ├── segmento_entity.dart                   # Implementa Syncable
│   │   ├── imagen_segmento_entity.dart            # Implementa Syncable
│   │   ├── position_batch_entity.dart             # Lote GPS — implementa Syncable
│   │   ├── ct_info_entity.dart
│   │   ├── gasoducto_entity.dart
│   │   └── user_entity.dart
│   ├── repository/
│   │   ├── segmento_repository.dart               # Interface
│   │   └── auth_repository.dart                   # Interface
│   └── usecases/
│       ├── get_segmentos_usecase.dart
│       └── update_segmento_estado_usecase.dart
├── data/
│   ├── local/
│   │   └── local_database.dart                    # Wrapper sobre OfflineDatabase + tablas master
│   ├── network/
│   │   ├── network_service.dart                   # Dio + interceptor HMAC + retry transporte
│   │   ├── network_error.dart                     # NetworkErrorCategory + NetworkError
│   │   └── sync_outcome_from_network_error.dart   # Mapper + 401 → AuthExpiredException
│   ├── model/
│   │   ├── mensaje_entity.dart                    # MensajeSegmentoEntity (Syncable)
│   │   └── ...
│   ├── providers/
│   │   └── auth_data_provider.dart                # Solo auth queda como provider standalone
│   ├── repository/
│   │   ├── auth_repository_impl.dart
│   │   ├── segmento_repository_impl.dart          # Usa OfflineRepository<SegmentoEntity>
│   │   ├── imagen_repository_impl.dart            # Usa OfflineRepository<ImagenSegmentoEntity>
│   │   └── mensaje_segmento_repository.dart       # Push via motor + lectura online (TODO §12.1)
│   └── sync/                                      # Adapters/stores específicos por entidad
│       ├── segmento_local_store.dart
│       ├── segmento_remote_adapter.dart
│       ├── segmento_remote_fetcher.dart
│       ├── imagen_local_store.dart
│       ├── imagen_remote_adapter.dart
│       ├── mensaje_local_store.dart
│       ├── mensaje_remote_adapter.dart
│       ├── position_local_store.dart
│       └── position_batch_remote_adapter.dart
└── presentation/
    ├── auth/
    │   ├── login_page.dart
    │   ├── login_page_binding.dart
    │   └── login_page_controller.dart
    ├── segmentos/                                 # Listado de segmentos
    │   ├── segmentos_list_page.dart
    │   ├── segmentos_list_binding.dart
    │   └── segmentos_list_controller.dart
    ├── detalle/                                   # Detalle de segmento + edición
    │   ├── segmento_detalle_page.dart
    │   ├── segmento_detalle_binding.dart
    │   ├── segmento_detalle_controller.dart
    │   └── edit_extremos/
    ├── camera/                                    # Captura de fotos
    │   └── camera_capture_page.dart
    ├── forzar_envio/                              # Atajo "subir todo lo de esta entidad"
    │   ├── forzar_envio_page.dart
    │   ├── forzar_envio_binding.dart
    │   └── forzar_envio_controller.dart
    ├── sincronizacion/                            # Sync page con 3 secciones + Preparar campo
    │   ├── sincronizacion_page.dart
    │   ├── sincronizacion_binding.dart
    │   ├── sincronizacion_controller.dart
    │   ├── sync_models.dart                       # DTOs UI: PendingByEntity, ConflictRow, ...
    │   └── field_work_tasks.dart                  # PipelineTasks de "Preparar trabajo de campo"
    └── mapa/
        ├── mapa_global_page.dart
        ├── mapa_global_binding.dart
        ├── mapa_global_controller.dart            # Arranca/para GpsBackgroundService
        ├── lines_cut/
        └── legacy/
```

---

## Rutas

| Constante | Path | Página | Protegida |
|---|---|---|---|
| `AppRoutes.login` | `/login` | `LoginPage` | No |
| `AppRoutes.segmentos` | `/segmentos` | `SegmentosListPage` | Sí (`AuthMiddleware`) |
| `AppRoutes.detalle` | `/segmentos/detalle` | `SegmentoDetallePage` | Sí |
| `AppRoutes.camera` | `/camera` | `CameraCapturePage` | Sí |
| `AppRoutes.mapa` | `/mapa` | `MapaGlobalPage` | Sí |
| `AppRoutes.sincronizacion` | `/sincronizacion` | `SincronizacionPage` | Sí (`AuthMiddleware`) |
| `AppRoutes.forzarEnvio` | `/forzar-envio` | `ForzarEnvioPage` | Sí (`AuthMiddleware`) |

---

## Entidades de Dominio

Todas las entidades sincronizables implementan `Syncable` (`clientId` UUID v4 inmutable, `remoteId?` asignado por backend, `updatedAt`). El concepto de `ActividadEntity` ya no existe: sus campos viven dentro de `SegmentoEntity` (estado, fechas, tipoActividad).

### `SegmentoEntity` — `Syncable`, push + pull
| Campo | Tipo | Descripción |
|---|---|---|
| `clientId` | `String` | UUID v4 inmutable (PK lógica del dominio) |
| `id` | `int?` | ID remoto del backend (nullable hasta primer sync) |
| `ctId` | `int` | Código CT Enagas (entero) |
| `nombre` | `String?` | |
| `descripcion` | `String` | |
| `traza` | `String?` | |
| `tipoInstalacion` | `TipoInstalacion` | concentrada, lineal |
| `pkInicio/Fin` | `double?` | PK kilométrico |
| `lat/lngInicio`, `lat/lngFin` | `double?` | |
| `ubicacionGis` | `List<LatLng>` | Polilínea parseada de GeoJSON |
| `tipoActividad` | `TipoActividad` | deshierbeSelectivo, desbroceManual… |
| `estado` | `EstadoActividad` | propuesta, validada, ejecución, finalizada, cerrada |
| `imagenes` | `List<ImagenSegmentoEntity>` | |
| `mensajes` | `List<MensajeSegmentoEntity>` | |
| `createdAt`, `fechaInicio`, `fechaFin` | `DateTime?` | |
| `updatedAt` | `DateTime` | escrito por `touchUpdated()` en cada cambio |
| `longitud` / `longitudKm` | getters | Haversine sobre `ubicacionGis` |

### `ImagenSegmentoEntity` — `Syncable`, push only
| Campo | Tipo | Descripción |
|---|---|---|
| `clientId` | `String` | UUID v4 |
| `id` | `int?` | ID remoto tras upload |
| `actividadId`, `segmentoId` | `int` | |
| `tipoFoto` | `TipoFoto` | antes, despues |
| `filename`, `ruta`, `url` | `String` | local/remote |
| `mimeType`, `tamanyoBytes` | | |
| `latitud`, `longitud`, `fixedLatitud`, `fixedLongitud` | `double?` | |
| `capturadaAt`, `subidaAt`, `createdAt`, `updatedAtRemote` | `DateTime?` | |
| `subidaPor` | `int?` | |

### `MensajeSegmentoEntity` — `Syncable`, push only (lectura online por ahora)
| Campo | Tipo |
|---|---|
| `clientId` | `String` UUID |
| `id` | `int?` |
| `segmentoId` | `int` |
| `mensaje` | `String` |
| `enviadoPor` | `int?` |
| `createdAt`, `updatedAt` | `DateTime` |

### `PositionBatchEntity` — `Syncable`, push only (GPS)
Lote de hasta ~500 puntos GPS. La unidad de sincronización del tracking.
| Campo | Tipo |
|---|---|
| `clientId` (= `batch_client_id`) | `String` UUID |
| `id` | `int?` (remote_id) |
| `operadorId` | `int` |
| `points` | `List<PositionPoint>` |
| `startedAt`, `endedAt` | `DateTime` |

### `UserEntity`
NO es `Syncable` — se obtiene en login y vive como info de sesión.
| Campo | Tipo |
|---|---|
| `id` | `int` |
| `usuario`, `nombre` | `String` |
| `cts` | `List<CtInfo>` |
| `token` | `String` |

---

## Controladores

| Controlador | Archivo | Responsabilidad clave |
|---|---|---|
| `LoginPageController` | `presentation/auth/` | Login, toggle password, último usuario, parse errores |
| `SegmentosListController` | `presentation/segmentos/` | Lee local de segmentos, filtra por estado, navega a detalle |
| `SegmentoDetalleController` | `presentation/detalle/` | Cambia estado, edita descripción, gestiona mensajes |
| `EditExtremosController` | `presentation/detalle/edit_extremos/` | Edición de extremos del segmento sobre el mapa |
| `CameraCaptureController` | `presentation/camera/` | Captura cámara → enqueue al outbox vía `OfflineRepository` |
| `MapaGlobalController` | `presentation/mapa/` | Mapa global; arranca/para `GpsBackgroundService` en su ciclo |
| `LinesCutController` | `presentation/mapa/lines_cut/` | Modo "líneas de corte" — segmenta gasoductos en mapa |
| `SincronizacionController` | `presentation/sincronizacion/` | Sync page con 3 secciones + "Preparar trabajo de campo" |
| `ForzarEnvioController` | `presentation/forzar_envio/` | "Subir": drena el outbox (segmento/imagen/mensaje) vía `SyncEngine.drain` por tipo; guard offline; corta al primer `authExpired` |
| `SplashController` | `presentation/splash/` | Ruta inicial; `await AppDI.init()` con spinner/reintentar antes de navegar a login |

### GetxServices (globales, permanent: true)

| Servicio | Responsabilidad |
|---|---|
| `ConnectivityService` | Monitoriza red; dispatcha `SyncActions.connectionRestored/Lost` (informativo, NO dispara drain) |
| `NetworkService` | Cliente Dio singleton con interceptor HMAC + retry de transporte |
| `GpsService` | Permisos de ubicación |
| `GpsBackgroundService` | Tracking GPS con buffer 500/30s; lifecycle atado al mapa |
| `JsonLoaderService` | Descarga GeoJSON multi-archivo (pipeline para gasoductos/PKs) |
| `GasoductosService` | Master data legacy de trazas (no integrado al motor — ver §12.2 doc backend) |
| `PksService` | Master data legacy de puntos kilométricos |
| `AuthExpirationHandler` | Listener global de `SyncActions.authExpired` → logout + nav login |
| `TypeRegistry` | Registro de tipos del motor (poblado por `OfflineModule.registerEntity`) |
| `OutboxQueue` | Cola persistente de operaciones pendientes |
| `SyncEngine` | Motor de drain del outbox (manual, sin retry/backoff) |
| `OfflineRepository<T>` | Por entidad con adapter — registrado por `OfflineModule` |
| `PullCoordinator<T>` | Por entidad con fetcher — registrado por `OfflineModule` |

---

## Casos de Uso

| Caso de Uso | Firma | Descripción |
|---|---|---|
| `GetSegmentosUseCase` | `execute(int operadorId, List<int> cts) → Future<DataResult<List<SegmentoEntity>>>` | Lee segmentos del store local (offline-first) |
| `UpdateSegmentoEstadoUseCase` | `execute(int id, EstadoActividad) → Future<DataResult<bool>>` | Actualiza estado vía `OfflineRepository` (local + outbox) |

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

- **HMAC-SHA256** sobre cada petición: `ApiSecurityService` genera el header firmado con `AppConfig.hmacSecret`
- `NetworkService` añade el header via interceptor Dio antes de cada request
- Token de usuario almacenado en `flutter_secure_storage`

---

## Dependencias Clave (pubspec.yaml)

| Paquete | Versión | Uso |
|---|---|---|
| `get` | `^4.7.3` | State management, navegación, DI |
| `dio` | `^5.9.2` | HTTP client |
| `flutter_map` | `^8.3.0` | Mapas |
| `flutter_map_cancellable_tile_provider` | `^3.1.1` | Tiles cancelables |
| `latlong2` | `^0.9.1` | Coordenadas |
| `sqflite` | `^2.4.2` | SQLite local |
| `image_picker` | `^1.2.1` | Galería |
| `camera` | `^0.12.0+1` | Cámara |
| `photo_view` | `^0.15.0` | Zoom de fotos |
| `cached_network_image` | `^3.4.1` | Cache de imágenes |
| `connectivity_plus` | `^7.1.1` | Estado de red |
| `flutter_secure_storage` | `^10.0.0` | Token seguro |
| `shared_preferences` | `^2.5.5` | Preferencias ligeras |
| `crypto` | `^3.0.7` | HMAC |
| `uuid` | `^4.5.3` | IDs únicos locales |
| `logger` | `^2.7.0` | Logging con niveles |
| `permission_handler` | `^12.0.1` | Permisos runtime |
| `intl` | `^0.20.2` | Fechas/i18n |
| `geolocator` | `^14.0.2` | GPS stream (foreground + iOS background) |
| `flutter_foreground_task` | `^9.2.2` | Foreground service Android para GPS |
| `leulit_flutter_actionmanager` | `^5.6.0` | TypedAction bus entre capas |
| `leulit_pipeline_pattern` | path | TaskPipeline para flujos secuenciales async |
| `mocktail` | `^1.0.5` (dev) | Tests |

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

---

## Pendiente / TODO

### Backend (entregable en `docs/BACKEND_SYNC_CONTRACT.md`)
- Idempotencia por `client_id` en TODOS los endpoints sincronizables.
- FKs entre entidades por `client_id` (no `remote_id`).
- `error_message` legible en español en respuestas 4xx (especialmente 422).
- `GET /mensajes?operador=X` para pull global de mensajes (§12.1) — hasta entonces lectura online + merge con pendientes locales.
- `GET /api/gasoductos` y `GET /api/pks` REST únicos para integrar master data al motor (§12.2) — hasta entonces flujo legacy multi-archivo GeoJSON.
- `POST /positions/batch` idempotente por `batch_client_id` (§8) para subida GPS.
- `updated_at` ISO8601 UTC en TODAS las entidades sincronizables.

### Plataforma — al publicar (config nativa ya cableada en repo)
- Android: minSdk **34**, manifest declara `FOREGROUND_SERVICE_LOCATION` y el `<service>` del plugin con `foregroundServiceType="location"`.
- iOS: deployment target **13.0**, `Info.plist` lleva `UIBackgroundModes=[location, fetch, processing]` + las tres descripciones `NSLocation…UsageDescription`.
- Justificaciones Play Console / App Store para `FOREGROUND_SERVICE_LOCATION` y modos de fondo iOS al primer release (trámite estándar para tracking apps).

### Cliente
- Reescribir `GasoductosService` y `PksService` al motor cuando backend tenga endpoints REST (ver §12.2 doc backend).
- Migrar lectura de `MensajeSegmento` al motor cuando backend exponga endpoint de pull global (§12.1).
- Filtro de solapamientos del corte contra segmentos existentes (`docs/LINES_CUT_MOBILE_INTEGRATION.md` §8).
- `AppConfig.hmacSecret` hardcodeado — migrar a variable de entorno / secret CI/CD.
- Extraer `lib/core/sync/` a paquete `leulit_offline_sync` cuando madure.
