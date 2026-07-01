# Referencia de Arquitectura — Módulo Desherbaje (Helireport Enagas)

Referencia de arquitectura detallada del módulo Desherbaje. Mantener sincronizado con el código — ver regla de auto-mantenimiento en [`CLAUDE.md`](../CLAUDE.md).

Catálogo extraído de CLAUDE.md para no inflar el fichero de instrucciones ni desincronizarlo. Contiene: estructura de `lib/`, rutas, entidades de dominio, controladores, GetxServices, casos de uso y dependencias.

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
│   │   ├── api_security_service.dart              # Generación headers HMAC — dos esquemas: legacy (x-flutter-*, segundos, nonce) y vídeo (X-HMAC-Signature, ms, sin nonce)
│   │   ├── auth_expiration_handler.dart           # Listener global de SyncActions.authExpired
│   │   ├── connectivity_service.dart              # GetxService: monitoriza red
│   │   ├── gasoductos_service.dart                # Master data legacy (no integrado al motor)
│   │   ├── gps_background_service.dart            # GPS background con buffer 500/30s + permisos de ubicación
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
│   │   ├── video_segmento_entity.dart             # Implementa Syncable — TipoVideo, uploadOffset, uploadId; remoteId = uploadId ?? id
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
│   │   ├── network_service.dart                   # Dio + interceptor HMAC legacy + retry transporte; _videoDio separado (4 min, sin interceptors) con 4 métodos de vídeo
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
│   │   ├── video_repository_impl.dart             # Usa OfflineRepository<VideoSegmentoEntity>
│   │   └── mensaje_segmento_repository.dart       # Push via motor + lectura online (TODO §12.1)
│   └── sync/                                      # Adapters/stores específicos por entidad
│       ├── segmento_local_store.dart
│       ├── segmento_remote_adapter.dart
│       ├── segmento_remote_fetcher.dart
│       ├── imagen_local_store.dart
│       ├── imagen_remote_adapter.dart
│       ├── video_local_store.dart                 # tabla videos_segmento + saveUploadOffset() + saveUploadId()
│       ├── video_remote_adapter.dart              # TUS-like adapter: Init→Chunk(PATCH)→Status(GET)→Complete; retry por chunk; 401/403=SyncUnrecoverable(no logout)
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

### `VideoSegmentoEntity` — `Syncable`, push only
| Campo | Tipo | Descripción |
|---|---|---|
| `clientId` | `String` | UUID v4. Inmutable. Clave de idempotencia en el Init del servidor |
| `id` | `int?` | ID numérico remoto (solo si el backend lo asigna, normalmente `null` para vídeos) |
| `uploadId` | `String?` | UUID asignado por el servidor en el Init. Persiste en SQLite. `remoteId` getter retorna `uploadId ?? id?.toString()` |
| `actividadId`, `segmentoId` | `int` | |
| `tipoVideo` | `TipoVideo` | antes, despues |
| `filename`, `ruta`, `url` | `String` | local/remote |
| `mimeType` | `String` | `video/mp4` (default), `video/quicktime` |
| `tamanyoBytes` | `int?` | |
| `uploadOffset` | `int` | Último byte confirmado (SQLite only, excluido de `toJson()`) |
| `latitud`, `longitud` | `double?` | |
| `capturadaAt` | `DateTime` | |
| `subidaAt`, `createdAt`, `updatedAtRemote` | `DateTime?` | |

Subida TUS-like via `NetworkService` (Init→PATCH chunks→Complete; 5 MB/chunk, 4 min timeout/chunk). Esquema HMAC exclusivo de vídeo (`X-HMAC-Signature`/`X-Timestamp` ms, sin Bearer). Backend remuxea `.mov→.mp4`. Protocolo completo: `docs/BACKEND_VIDEO_CONTRACT.md`.

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
| `ForzarEnvioController` | `presentation/forzar_envio/` | "Subir": drena el outbox (segmento/imagen/video/mensaje) vía `SyncEngine.drain` por tipo; guard offline; corta al primer `authExpired` |
| `SplashController` | `presentation/splash/` | Ruta inicial; `await AppDI.init()` con spinner/reintentar antes de navegar a login |

### GetxServices (globales, permanent: true)

| Servicio | Responsabilidad |
|---|---|
| `ConnectivityService` | Monitoriza red; dispatcha `SyncActions.connectionRestored/Lost` (informativo, NO dispara drain) |
| `NetworkService` | Cliente Dio singleton con interceptor HMAC + retry de transporte |
| `GpsBackgroundService` | Tracking GPS con buffer 500/30s + permisos de ubicación; lifecycle atado al mapa |
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
