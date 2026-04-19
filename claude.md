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
│   ├── app_di.dart                                # Dependency injection global
│   ├── app_router.dart                            # AppRoutes + AppPages + AuthMiddleware
│   ├── app_theme.dart                             # Colores, TextStyles, espaciado
│   └── services/
│       ├── api_security_service.dart              # Generación headers HMAC
│       ├── connectivity_service.dart              # GetxService: monitoriza red
│       └── gps_service.dart                       # GetxService: permisos de ubicación
├── domain/
│   ├── entities/
│   │   ├── actividad_entity.dart
│   │   ├── segmento_entity.dart
│   │   ├── imagen_actividad_entity.dart
│   │   └── user_entity.dart
│   ├── repository/
│   │   ├── actividad_repository.dart              # Interface
│   │   └── auth_repository.dart                   # Interface
│   └── usecases/
│       ├── get_actividades_usecase.dart
│       ├── update_actividad_usecase.dart
│       └── upload_image_usecase.dart
├── data/
│   ├── local/
│   │   └── local_database.dart                    # SQLite via sqflite
│   ├── network/
│   │   └── network_service.dart                   # Dio + interceptor HMAC
│   ├── providers/
│   │   ├── actividad_data_provider.dart           # Interface
│   │   ├── actividad_data_provider_factory.dart   # Factory online/offline
│   │   ├── actividad_data_provider_online.dart
│   │   ├── actividad_data_provider_offline.dart
│   │   ├── auth_data_provider.dart
│   │   └── image_upload_provider.dart
│   └── repository/
│       ├── actividad_repository_impl.dart
│       ├── auth_repository_impl.dart
│       └── imagen_repository_impl.dart
└── presentation/
    ├── auth/
    │   ├── login_page.dart
    │   ├── login_page_binding.dart
    │   └── login_page_controller.dart
    ├── actividades/
    │   ├── actividades_list_page.dart
    │   ├── actividades_list_binding.dart
    │   └── actividades_list_controller.dart
    ├── detalle/
    │   ├── actividad_detalle_page.dart
    │   ├── actividad_detalle_binding.dart
    │   └── actividad_detalle_controller.dart
    ├── fotos/
    │   ├── captura_fotos_page.dart
    │   ├── captura_fotos_binding.dart
    │   └── captura_fotos_controller.dart
    ├── mapa/                                       # Pendiente de implementación
    └── widgets/
        ├── actividad_card_widget.dart
        ├── estado_badge_widget.dart
        ├── segmento_card_widget.dart
        └── upload_progress_widget.dart
```

---

## Rutas

| Constante | Path | Página | Protegida |
|---|---|---|---|
| `AppRoutes.login` | `/login` | `LoginPage` | No |
| `AppRoutes.actividades` | `/actividades` | `ActividadesListPage` | Sí (`AuthMiddleware`) |
| `AppRoutes.detalle` | `/actividades/detalle` | `SegmentoDetallePage` | Sí |
| `AppRoutes.fotos` | `/actividades/fotos` | `CapturaFotosPage` | Sí |

---

## Entidades de Dominio

### `ActividadEntity`
| Campo | Tipo | Descripción |
|---|---|---|
| `id` | `int` | ID remoto |
| `posicionId` | `int` | Referencia a posición/instalación |
| `tipoActividad` | `TipoActividad` | desherbajeSelectivo, desbroceManual, desbroceMecanico, desratizacion |
| `estado` | `EstadoActividad` | propuesta, validada, ejecucion, finalizada, cerrada |
| `descripcion` | `String` | Texto libre |
| `superficieM2` | `double?` | Superficie en m² |
| `costeEstimado` | `double?` | Coste en € |
| `fechaProgramada` | `DateTime?` | |
| `fechaInicio` / `fechaFin` | `DateTime?` | |
| `segmentos` | `List<SegmentoEntity>` | |
| `longitudTotal` | getter `double` | Suma longitudes de segmentos |

### `SegmentoEntity`
| Campo | Tipo | Descripción |
|---|---|---|
| `id` | `int` | |
| `ctId` | `String` | Código CT Enagas |
| `nombre` | `String` | |
| `traza` | `String?` | |
| `tipoInstalacion` | `TipoInstalacion` | concentrada, lineal |
| `pkInicio/Fin` | `double?` | PK kilométrico |
| `lat/lngInicio`, `lat/lngFin` | `double?` | |
| `ubicacionGis` | `List<LatLng>` | Polilínea parseada de GeoJSON |
| `longitud` / `longitudKm` | getters | Haversine sobre `ubicacionGis` |
| `ubicacionGisAsGeoJSON` | getter `String` | Serializa a GeoJSON para API |

### `ImagenSegmentoEntity`
| Campo | Tipo | Descripción |
|---|---|---|
| `localId` | `int?` | ID SQLite local |
| `remoteId` | `int?` | ID tras subida exitosa |
| `actividadId` | `int` | |
| `segmentoId` | `int?` | |
| `localPath` | `String` | Ruta en dispositivo |
| `remoteUrl` | `String?` | URL tras subida |
| `tipoFoto` | `TipoFoto` | antes, despues |
| `capturedAt` | `DateTime` | |
| `latitude/longitude` | `double?` | GPS en captura |
| `syncStatus` | `SyncStatus` | pending, uploading, uploaded, error |

### `UserEntity`
| Campo | Tipo |
|---|---|
| `id` | `int` |
| `usuario` | `String` |
| `nombre` | `String` |
| `cts` | `List<String>` |
| `token` | `String` |

---

## Controladores

| Controlador | Archivo | Responsabilidad clave |
|---|---|---|
| `LoginPageController` | `presentation/auth/` | Login, toggle password, último usuario, parse errores |
| `ActividadesListController` | `presentation/actividades/` | Carga lista, filtra por `EstadoActividad`, navega a detalle |
| `SegmentoDetalleController` | `presentation/detalle/` | Cambia estado de actividad, navega a fotos |
| `CapturaFotosController` | `presentation/fotos/` | Captura (cámara/galería), gestiona `SyncStatus`, sube pendientes, borra |

### GetxServices (globales, no se destruyen)

| Servicio | Responsabilidad |
|---|---|
| `ConnectivityService` | Monitoriza red; dispara auto-sync cuando vuelve conectividad |
| `GpsService` | Gestiona permisos de ubicación |
| `NetworkService` | Cliente Dio singleton con interceptor HMAC |

---

## Casos de Uso

| Caso de Uso | Firma | Descripción |
|---|---|---|
| `GetActividadesUseCase` | `execute() → Future<List<ActividadEntity>>` | Obtiene lista desde provider (online/offline) |
| `UpdateActividadUseCase` | `execute(int id, EstadoActividad) → Future<bool>` | Actualiza estado en backend |
| `UploadImageUseCase` | `uploadPending(int actividadId) → Future<void>` | Sube imágenes con `SyncStatus.pending` |

---

## Offline-First (Factory Pattern)

```dart
// Cada dominio tiene: interface + factory + online + offline
final provider = ActividadDataProviderFactory.create(); // auto-switch según conectividad
// ConnectivityService determina qué implementación se devuelve
```

- **Online:** llama a la API REST con Dio + HMAC
- **Offline:** lee/escribe en SQLite local (`local_database.dart`)
- **Sync:** `ConnectivityService` detecta reconexión → `UploadImageUseCase.uploadPending()`

---

## Seguridad de Red

- **HMAC-SHA256** sobre cada petición: `ApiSecurityService` genera el header firmado con `AppConfig.hmacSecret`
- `NetworkService` añade el header via interceptor Dio antes de cada request
- Token de usuario almacenado en `flutter_secure_storage`

---

## Dependencias Clave (pubspec.yaml)

| Paquete | Versión | Uso |
|---|---|---|
| `get` | `^4.7.2` | State management, navegación, DI |
| `dio` | `^5.7.0` | HTTP client |
| `flutter_map` | `^8.2.2` | Mapas |
| `flutter_map_cancellable_tile_provider` | `^3.1.1` | Tiles cancelables |
| `latlong2` | `^0.9.1` | Coordenadas |
| `sqflite` | `^2.3.3+2` | SQLite local |
| `image_picker` | `^1.1.2` | Galería |
| `camera` | `^0.12.0+1` | Cámara |
| `photo_view` | `^0.15.0` | Zoom de fotos |
| `cached_network_image` | `^3.4.1` | Cache de imágenes |
| `connectivity_plus` | `^7.0.0` | Estado de red |
| `flutter_secure_storage` | `^10.0.0` | Token seguro |
| `shared_preferences` | `^2.3.3` | Preferencias ligeras |
| `crypto` | `^3.0.3` | HMAC |
| `uuid` | `^4.5.1` | IDs únicos locales |
| `logger` | `^2.4.0` | Logging con niveles |
| `permission_handler` | `^12.0.1` | Permisos runtime |
| `intl` | `^0.20.2` | Fechas/i18n |
| `mocktail` | `^1.0.4` | Tests (dev) |

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
- **Offline-first**: DataProviderFactory, SQLite local, sync automático al reconectar
- **UX**: Minimizar clicks, feedback instantáneo, jerarquía visual clara
- **Platform-aware**: Comportamiento específico web/iOS/Android en marcadores, polilíneas, tooltips

---

## Lecciones Aprendidas

*(Se irán añadiendo a medida que se corrijan bugs recurrentes)*

---

## Pendiente / TODO

- Módulo `mapa/` — visualización de segmentos en flutter_map
- Barrel exports (`export_*.dart`) — aún no creados
- `AppConfig.hmacSecret` hardcodeado — migrar a variable de entorno o secret en CI/CD
