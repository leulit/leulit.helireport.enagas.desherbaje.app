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
│   ├── gis/                                        # GIS de captura de media (foto/vídeo)
│   │   ├── media_gis_recorder.dart                # MediaGisSample + MediaGisRecorder (streams propios geolocator 1s + flutter_rotation_sensor); independiente del GpsBackgroundService
│   │   ├── media_gis_geojson.dart                 # Puro/sin IO: buildPhotoGeoJson / buildVideoGeoJson → FeatureCollection (null sin muestra)
│   │   ├── capture_meta.dart                       # CaptureMeta (device_info_plus + package_info_plus); captureMeta() memoizado
│   │   └── media_gis_map_geometry.dart             # Puro/sin IO: parsePhotoGis/parseVideoGis (lee gis_json) + destinationPoint/arrowGeometry (flecha) + VideoVertex/parseVideoTrack (rumbo por vértice)/directionBandPolygon (banda de dirección de cámara del vídeo) para pintar en el mapa
│   ├── services/
│   │   ├── api_security_service.dart              # Generación headers HMAC — dos esquemas: legacy (x-flutter-*, segundos, nonce) y vídeo (X-HMAC-Signature, ms, sin nonce)
│   │   ├── auth_expiration_handler.dart           # Listener global de SyncActions.authExpired
│   │   ├── connectivity_service.dart              # GetxService: monitoriza red
│   │   ├── gasoductos_service.dart                # Master data legacy (no integrado al motor)
│   │   ├── gps_background_service.dart            # Grabación manual de "traza" (GpsTrackingState vía ValueNotifier); buffer 500/30s; start()/finish(name)/openTrazaFor()/finalizeOpen()
│   │   ├── pks_service.dart                       # Master data PK legacy
│   │   └── hitos_service.dart                     # Master data hitos legacy (réplica de PksService)
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
│   │   ├── traza_entity.dart                      # TrazaEntity (implementa Syncable) + TrazaPunto — traza GPS manual, push only
│   │   ├── posicion_fija_entity.dart              # Implementa Syncable — pull-only; displayLatitude/Longitude (fixed_* > latitud/longitud)
│   │   ├── ct_info_entity.dart
│   │   ├── gasoducto_entity.dart
│   │   ├── pk_entity.dart                         # Punto kilométrico (marcador mapa)
│   │   ├── hito_entity.dart                       # Hito (marcador mapa — misma forma que PkEntity)
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
│       ├── traza_local_store.dart                 # tablas trazas + trazas_puntos; appendPoints/findOpen/findAnyOpen/finalize/deleteSynced además del contrato LocalStore
│       ├── traza_remote_adapter.dart              # POST /trazas — body = buildTrackGeoJson (FeatureCollection/MultiLineString), push-only (create), idempotente por traza_client_id
│       ├── posicion_fija_local_store.dart         # tabla posiciones_fijas — pull-only, sin outbox
│       └── posicion_fija_remote_fetcher.dart      # GET /incidencias/posicionesfijasbycts/{cts}
└── presentation/
    ├── auth/
    │   ├── login_page.dart                        # incluye enlace "¿Contraseña olvidada?"
    │   ├── login_page_binding.dart
    │   ├── login_page_controller.dart             # forgotPassword(): dialog email → pide OTP → navega a ResetPasswordPage
    │   └── reset_password_page.dart               # OTP: código 6 dígitos + nueva contraseña (StatefulWidget, setState); Get.to desde login
    ├── segmentos/                                 # Listado de segmentos
    │   ├── segmentos_list_page.dart
    │   ├── segmentos_list_binding.dart
    │   └── segmentos_list_controller.dart
    ├── detalle/                                   # Detalle de segmento + edición
    │   ├── segmento_detalle_page.dart
    │   ├── segmento_detalle_binding.dart
    │   ├── segmento_detalle_controller.dart
    │   ├── segmento_media_item.dart                # SegmentoMediaItem: view-model unificado foto/vídeo (incluye gisJson)
    │   ├── media_gis_layer.dart                    # MediaGisLayer (GetView<MediaGisLayerController>, sin Obx) + MediaGisLayerController: ValueNotifier<MediaGisGeometry> (polígonos/polylines/markers) pintado con ValueListenableBuilder; georreferencia de la media activa del carrusel + banda de dirección de vídeo + dispatch de mediaGisBoundsRequested
    │   └── edit_extremos/
    ├── camera/                                    # Captura de fotos/vídeos
    │   ├── camera_capture_page.dart               # Selector Foto|Vídeo (vídeo sin audio)
    │   └── video_player_page.dart                 # Reproductor pantalla completa (local)
    ├── forzar_envio/                              # Atajo "subir todo lo de esta entidad"
    │   ├── forzar_envio_page.dart                 # + _ResetButton (solo superadmin): OfflineDatabase.wipeAll + logout
    │   ├── forzar_envio_binding.dart
    │   └── forzar_envio_controller.dart
    ├── sincronizacion/                            # Sync page con 3 secciones + Preparar campo
    │   ├── sincronizacion_page.dart
    │   ├── sincronizacion_binding.dart
    │   ├── sincronizacion_controller.dart
    │   ├── sync_models.dart                       # DTOs UI: PendingByEntity, ConflictRow, ...
    │   └── field_work_tasks.dart                  # PipelineTasks de "Preparar trabajo de campo"
    ├── widgets/                                   # Compartidos entre pantallas (AppBar actions, diálogos)
    │   ├── track_record_button.dart               # AppBar action: inicia/finaliza la traza vía GpsBackgroundService; ValueListenableBuilder<GpsTrackingState>
    │   ├── logout_button.dart                     # AppBar action "cerrar sesión" compartida; bloquea logout si AppTypedActions.isTrazaRecording()
    │   ├── finalize_traza_dialog.dart              # showFinalizeTrazaDialog(): diálogo no descartable para nombrar la traza al finalizar (manual o recuperación de crash)
    │   └── forgot_password_dialog.dart             # showForgotPasswordDialog(): pide el email para "¿Contraseña olvidada?" (login); devuelve email o null
    └── mapa/
        ├── mapa_global_page.dart
        ├── mapa_global_binding.dart
        ├── mapa_global_controller.dart            # Ya NO arranca/para GpsBackgroundService — la grabación es independiente de esta pantalla (ver TrackRecordButton)
        ├── layers/
        │   ├── segmentos_map_controller.dart
        │   ├── segmentos_map_layer.dart
        │   ├── clustered_marker_layer.dart        # Clustering supercluster + culling por viewport
        │   ├── point_label_marker.dart            # Etiqueta con pico, compartida PK/hito
        │   ├── hitos_map_layer.dart               # ValueListenableBuilder sobre AppDI.hitosService.hitos
        │   ├── posiciones_fijas_map_controller.dart  # Lee PosicionFijaLocalStore (DI get_it), pull-only
        │   ├── posiciones_fijas_map_layer.dart       # Clon visual de HitosMapLayer
        │   ├── gasoductos_map_layer.dart
        │   └── pks_map_layer.dart                 # ValueListenableBuilder sobre AppDI.pksService.pks
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
| `ctname` | `String` | Nombre del CT (default `''`). El CT viaja por NOMBRE, no por id (contrato §3 upsert / §8 descarga contratista) |
| `nombre` | `String?` | |
| `descripcion` | `String` | |
| `traza` | `String?` | |
| `tipoInstalacion` | `TipoInstalacion` | concentrada, lineal |
| `pkInicio/Fin` | `double?` | PK kilométrico |
| `lat/lngInicio`, `lat/lngFin` | `double?` | |
| `ubicacionGis` | `List<LatLng>` | Polilínea parseada de GeoJSON |
| `tipoActividad` | `TipoActividad` | 11 tipos: desbroceManual, desbroceMecanico, tala, resiembre, posicionDesherbajeTraza (default), tratamientoAvispas/Aranas/Reptiles y sus variantes `…Otros` |
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
| `gisJson` | `String?` | GeoJSON `FeatureCollection` de captura (`Point` + rumbo). `null` si sin fix/permiso o galería. Enviado al backend en `toJson` como `gis_json` |
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
| `gisJson` | `String?` | GeoJSON `FeatureCollection` de captura (`LineString` 1 muestra/seg con coord custom `[lon,lat,alt,heading_deg,t_epoch_ms]`; degrada a `Point` con 1 muestra). `null` si sin fix/permiso o galería. Enviado al backend en `toJson` como `gis_json` |
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

### `TrazaEntity` — `Syncable`, push only (GPS, `create` únicamente)
Traza GPS manual (nombre "traza" en toda la app y el backend). La unidad de sincronización es la traza completa (cabecera + puntos), no un lote parcial: el drain enqueda un único job por traza al finalizar la grabación. `endedAt == null` = traza abierta (grabando, o dejada abierta por un crash); el local store impone como máximo una traza abierta por operador.
| Campo | Tipo | Descripción |
|---|---|---|
| `clientId` (= `traza_client_id`) | `String` | UUID v4, generado al crear |
| `id` | `int?` | `remote_id` asignado por el backend; `remoteId` getter = `id?.toString()` |
| `operadorId` | `int` | |
| `startedAt` | `DateTime` | UTC |
| `endedAt` | `DateTime?` | `null` mientras está abierta |
| `name` | `String` | Default `'Traza yyyy-MM-dd HH:mm'` (hora local de `startedAt`); editable al finalizar vía `showFinalizeTrazaDialog`; clamp a 100 caracteres |
| `points` | `List<TrazaPunto>` | `capturedAt`, `lat`, `lng`, `accuracyMeters?`, `altitudeMeters?`, `speedMps?` — no son `Syncable`, nunca se sincronizan sueltos |

Tablas SQLite: `trazas` (cabecera) + `trazas_puntos` (uno por punto, FK `traza_client_id`). Reemplazan `posiciones_gps_batches`/`posiciones_gps`, borradas en la migración `schemaVersion 1` de `TrazaLocalStore` (app aún no en producción, sin backwards-compat). Payload de subida: `POST /trazas` con un `FeatureCollection`/`MultiLineString` (`buildTrackGeoJson` en `core/gis/media_gis_geojson.dart`), vértice de 6 posiciones `[lon, lat, alt, t_epoch_ms, accuracy_m, speed_mps]` (las cuatro últimas nullables salvo `t_epoch_ms`), partido en segmentos cuando el hueco entre dos puntos consecutivos supera 60 s; segmentos de 1 solo punto se descartan; sin ningún segmento superviviente el adapter devuelve éxito sin llamar a la red. Respuesta `200 {"id": N}`; si trae `received`/`stored`, el adapter loguea los vértices que el backend descartó en silencio.

### `PosicionFijaEntity` — `Syncable`, **pull only**
Posición fija (instalación/vigilancia) asociada a un CT. Se descarga y se muestra en el mapa; nunca se sube (sin outbox).
| Campo | Tipo | Descripción |
|---|---|---|
| `clientId` | `String` | UUID v4 |
| `id` | `int?` | ID remoto (`remoteId` = `id?.toString()`) |
| `title`, `ctname` | `String` | |
| `latitud`, `longitud` | `double?` | Llegan como `String` del backend; parseadas con `double.tryParse` |
| `fixedLatitude`, `fixedLongitude` | `double?` | Idem; pueden venir `"0.000000000"` (inválidas) |
| `zona`, `tramo`, `subtramo`, `tipoPunto`, `tipoVigilancia`, `trazaname`, `fotos` | `String?` | |
| `fecha` | `DateTime?` | |
| `updatedAt` | `DateTime` | Fallback determinista: `updated_at` → `iupdated` → `icreated` → `fecha` → epoch 0. Nunca `DateTime.now()` |
| `displayLatitude`/`displayLongitude` | getters | Prefieren `fixed_*` si son válidas (no null/NaN/0,0/fuera de rango), si no caen a `latitud/longitud` |
| `hasValidPoint` | getter | `true` si hay un punto válido para pintar en mapa |

Registrada en el motor solo con `fetcher` (sin `adapter`) — `OfflineModule.registerEntity<PosicionFijaEntity>(entityType: 'posicion_fija', ...)`. Endpoint: `GET /incidencias/posicionesfijasbycts/{cts}` (mismo esquema de nombres de CT que `segmentosByCt`). Capa de mapa: `PosicionesFijasMapController` (lee `PosicionFijaLocalStore` local) + `PosicionesFijasMapLayer` (clon visual de `HitosMapLayer`).

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
| `MapaGlobalController` | `presentation/mapa/` | Mapa global; ya NO controla el ciclo de vida de `GpsBackgroundService` (ver `TrackRecordButton`) |
| `LinesCutController` | `presentation/mapa/lines_cut/` | Modo "líneas de corte" — segmenta gasoductos en mapa |
| `PosicionesFijasMapController` | `presentation/mapa/layers/` | Lee `PosicionFijaLocalStore` (DI get_it) y expone marcadores válidos; solo lectura local, sin red |
| `SincronizacionController` | `presentation/sincronizacion/` | Sync page con 3 secciones + "Preparar trabajo de campo"; expone `isSuperadmin` + `resetAppData()` (wipe total, solo `UserRole.superadmin`) |
| `ForzarEnvioController` | `presentation/forzar_envio/` | "Subir": drena el outbox (segmento/imagen/video/mensaje/traza) vía `SyncEngine.drain` por tipo; guard offline; corta al primer `authExpired` |
| `SegmentosListController` | `presentation/segmentos/` | Además del listado: recuperación de traza huérfana tras crash (`_recoverOrphanedTraza`, primera pantalla con sesión activa tras login) |
| `SplashController` | `presentation/splash/` | Ruta inicial; `await AppDI.init()` con spinner/reintentar antes de navegar a login |

### GetxServices (globales, permanent: true)

| Servicio | Responsabilidad |
|---|---|
| `ConnectivityService` | Monitoriza red; dispatcha `SyncActions.connectionRestored/Lost` (informativo, NO dispara drain) |
| `NetworkService` | Cliente Dio singleton con interceptor HMAC + retry de transporte |
| `GpsBackgroundService` | Grabación manual de traza GPS (`start()`/`finish(name)`); buffer 500 puntos/30s flush append-only; `ValueNotifier<GpsTrackingState>`; foreground service Android (`stopWithTask=false`, sobrevive swipe de recientes) / `allowBackgroundLocationUpdates` iOS; lifecycle independiente de cualquier pantalla — activado por `TrackRecordButton` |
| `JsonLoaderService` | Descarga GeoJSON multi-archivo (pipeline para gasoductos/PKs) |
| `GasoductosService` | Master data legacy de trazas (no integrado al motor — ver §12.2 doc backend) |
| `PksService` | Master data legacy de puntos kilométricos; expone `pks` como `ValueNotifier<List<PkEntity>>` |
| `HitosService` | Master data legacy de hitos (réplica de `PksService`; tabla `hitos`, fichero `{filename}-hitos.json`); expone `hitos` como `ValueNotifier<List<HitoEntity>>` |
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
| `GetSegmentosUseCase` | `execute() → Future<DataResult<List<SegmentoEntity>>>` | Lee segmentos del store local (offline-first) filtrando por nombres de CT del usuario (`readCtNamesFromPrefs`, `user_json`) |
| `UpdateSegmentoEstadoUseCase` | `execute(int id, EstadoActividad) → Future<DataResult<bool>>` | Actualiza estado vía `OfflineRepository` (local + outbox) |

---

## Dependencias Clave (pubspec.yaml)

| Paquete | Versión | Uso |
|---|---|---|
| `get` | `^4.7.3` | State management, navegación, DI |
| `dio` | `^5.9.2` | HTTP client |
| `flutter_map` | `^8.3.0` | Mapas |
| `flutter_map_cancellable_tile_provider` | `^3.1.1` | Tiles cancelables |
| `supercluster` | `^3.2.0` | Clustering espacial de marcadores (PKs e hitos) |
| `latlong2` | `^0.9.1` | Coordenadas |
| `sqflite` | `^2.4.2` | SQLite local |
| `image_picker` | `^1.2.1` | Galería |
| `camera` | `^0.12.0+1` | Cámara |
| `video_player` | `^2.11.1` | Reproducción de vídeo local |
| `gal` | `^2.3.2` | Guardar fotos/vídeos en galería del dispositivo |
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
| `geolocator` | `^14.0.3` | GPS stream (foreground + iOS background) |
| `flutter_rotation_sensor` | `^0.3.0` | Rumbo (azimuth) para GIS de captura; funciona parado |
| `device_info_plus` | `^13.2.0` | `os`/`os_version`/`device_model` en `gis_json` (CaptureMeta) |
| `package_info_plus` | `^10.2.0` | `app_version` en `gis_json` (CaptureMeta) |
| `flutter_foreground_task` | `^10.0.0` | Foreground service Android para grabación de traza (`stopWithTask=false`) |
| `leulit_flutter_actionmanager` | `^5.6.0` | TypedAction bus entre capas |
| `leulit_pipeline_pattern` | path | TaskPipeline para flujos secuenciales async |
| `mocktail` | `^1.0.5` (dev) | Tests |
