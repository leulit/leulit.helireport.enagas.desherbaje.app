# dev-claude.md — Helireport Enagas Desherbaje App (Mobile)

> **Documento de especificación para agentes IA.** Este fichero es el punto de partida para desarrollar la aplicación móvil de desherbaje desde cero. Contiene todo lo necesario para crear, diseñar e implementar la app sin necesidad de consultar la webapp.

---

## Skills requeridos

Los siguientes skills deben activarse en el agente que ejecute el desarrollo. Están disponibles en  `.claude/skills/`:

```
@skills/flutter-core/SKILL.md
@skills/flutter-efficiency/SKILL.md
@skills/flutter-gis/SKILL.md
@skills/flutter-imaging/SKILL.md
@skills/flutter-backend-integration/SKILL.md
```

---

## 1. Contexto del Proyecto

### ¿Qué es esta app?
Aplicación móvil Flutter (Android + iOS) para **operadores de campo** de Enagas. Complementa el módulo de desherbaje de la webapp de gestión. Los operadores usan esta app en terreno para:

1. Ver las **actividades de desherbaje** asignadas a su zona (CTs)
2. Ver los **segmentos** georreferenciados sobre gasoductos donde deben trabajar
3. **Capturar fotos** antes y después de realizar los trabajos
4. **Asociar fotos** a segmentos específicos de una actividad
5. **Subir** todo al backend para que los gestores tengan evidencia de los trabajos

### Usuarios
- **Rol**: `operador` (ver `UserRole` enum de la webapp)
- **Contexto**: campo, posiblemente sin conectividad estable → offline-first obligatorio
- **Dispositivos**: Android e iOS, pantallas medianas (5–6.5")

### Backend compartido
Mismo backend que la webapp: `https://enagastool.helireport.com`
- Autenticación: HMAC-SHA256 (headers `x-flutter-signature`, `x-flutter-timestamp`, `x-flutter-nonce`)
- Todos los endpoints existen y están implementados

---

## 2. Setup Inicial del Proyecto

### Crear proyecto Flutter

```bash
flutter create \
  --org com.leulit.enagas \
  --project-name helireport_desherbaje \
  --platforms android,ios \
  leulit_helireport_enagas_desherbaje_app
```

### SDK y plataformas
- **Flutter SDK**: `>=3.11.0 <4.0.0`
- **Dart SDK**: `>=3.3.0 <4.0.0`
- **Android**: minSdkVersion 21, targetSdkVersion 34
- **iOS**: deployment target 14.0

### Dependencias (`pubspec.yaml`)

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Estado y DI
  get: ^4.7.3

  # HTTP y conectividad
  dio: ^5.9.2
  connectivity_plus: ^7.0.0

  # Mapas
  flutter_map: ^8.2.2
  latlong2: ^0.9.1
  flutter_map_cancellable_tile_provider: ^3.1.0

  # Cámara e imágenes
  image_picker: ^1.2.1
  camera: ^0.11.0
  photo_view: ^0.15.0
  cached_network_image: ^3.4.1

  # Almacenamiento local
  sqflite: ^2.4.2
  path_provider: ^2.1.4
  shared_preferences: ^2.5.4

  # Utilidades
  crypto: ^3.0.7          # HMAC-SHA256
  path: ^1.9.0
  intl: ^0.19.0
  uuid: ^4.5.1
  logger: ^2.5.0

  # Permisos
  permission_handler: ^11.3.1

  # Seguridad
  flutter_secure_storage: ^9.2.4

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  mocktail: ^1.0.4
```

### Estructura de carpetas (Clean Architecture)

```
lib/
├── main.dart
├── main_app.dart                    # GetMaterialApp + routing
│
├── core/
│   ├── app_config.dart              # URLs, constantes
│   ├── app_di.dart                  # Dependency Injection global
│   ├── app_router.dart              # Rutas GetX
│   ├── app_theme.dart               # Tema Material verde
│   ├── extensions.dart              # Extensions útiles
│   ├── my_getx_controller.dart      # Base controller
│   ├── services/
│   │   ├── api_security_service.dart    # HMAC-SHA256
│   │   ├── connectivity_service.dart    # Online/offline monitor
│   │   └── gps_service.dart            # Geolocalización
│   └── widgets/
│       └── auto_get_builder.dart
│
├── data/
│   ├── local/
│   │   └── local_database.dart      # SQLite
│   ├── network/
│   │   └── network_service.dart     # Dio + HMAC
│   ├── providers/
│   │   ├── actividad_data_provider.dart         # Abstract
│   │   ├── actividad_data_provider_online.dart
│   │   ├── actividad_data_provider_offline.dart
│   │   ├── actividad_data_provider_factory.dart
│   │   ├── auth_data_provider.dart
│   │   └── image_upload_provider.dart
│   └── repository/
│       ├── actividad_repository_impl.dart
│       └── auth_repository_impl.dart
│
├── domain/
│   ├── entities/
│   │   ├── actividad_entity.dart
│   │   ├── segmento_entity.dart
│   │   ├── imagen_actividad_entity.dart  # Nueva entidad mobile
│   │   └── user_entity.dart
│   ├── repository/
│   │   ├── actividad_repository.dart     # Interface
│   │   └── auth_repository.dart          # Interface
│   └── usecases/
│       ├── get_actividades_usecase.dart
│       ├── update_actividad_usecase.dart
│       └── upload_image_usecase.dart
│
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
    ├── mapa/
    │   ├── segmentos_mapa_page.dart
    │   ├── segmentos_mapa_binding.dart
    │   └── segmentos_mapa_controller.dart
    ├── fotos/
    │   ├── captura_fotos_page.dart
    │   ├── captura_fotos_binding.dart
    │   └── captura_fotos_controller.dart
    └── widgets/                     # Widgets compartidos
        ├── estado_badge_widget.dart
        ├── actividad_card_widget.dart
        ├── segmento_card_widget.dart
        └── upload_progress_widget.dart
```

---

## 3. Entidades de Dominio

> Estas entidades son **compartidas con la webapp**. El JSON shape debe ser idéntico para garantizar compatibilidad con el backend.

### 3.1 `ActividadEntity`

```dart
// Enum EstadoActividad
enum EstadoActividad {
  propuesta,
  validada,
  ejecucion,
  finalizada,
  cerrada;

  String get descripcion => name; // "propuesta", "validada", etc.
  String get etiqueta => switch (this) {
    propuesta  => 'Propuesta',
    validada   => 'Validada',
    ejecucion  => 'En Ejecución',
    finalizada => 'Finalizada',
    cerrada    => 'Cerrada',
  };
  static EstadoActividad fromString(String? s) =>
    EstadoActividad.values.firstWhere(
      (e) => e.descripcion == s?.toLowerCase(),
      orElse: () => EstadoActividad.propuesta,
    );
}

// Enum TipoActividad
enum TipoActividad {
  desherbajeSelectivo,
  desbroceManual,
  desbroceMecanico,
  desratizacion;

  String get descripcion => switch (this) {
    desherbajeSelectivo => 'desherbaje_selectivo',
    desbroceManual      => 'desbroce_manual',
    desbroceMecanico    => 'desbroce_mecanico',
    desratizacion       => 'desratizacion',
  };
  String get etiqueta => switch (this) {
    desherbajeSelectivo => 'Desherbaje Selectivo',
    desbroceManual      => 'Desbroce Manual',
    desbroceMecanico    => 'Desbroce Mecánico',
    desratizacion       => 'Desratización',
  };
  static TipoActividad fromString(String? s) =>
    TipoActividad.values.firstWhere(
      (e) => e.descripcion == s,
      orElse: () => TipoActividad.desherbajeSelectivo,
    );
}

// Entidad principal
class ActividadEntity {
  int id;                          // 0 si no tiene ID aún
  int posicionId;                  // FK al segmento principal
  TipoActividad tipoActividad;
  EstadoActividad estado;
  String descripcion;
  double superficieM2;
  double costeEstimado;
  DateTime fechaProgramada;
  DateTime fechaInicio;
  DateTime fechaFin;
  List<SegmentoEntity> segmentos;  // Segmentos de la actividad

  // Computed
  double get longitudTotal =>
    segmentos.fold(0.0, (sum, s) => sum + s.longitud);

  // JSON keys: id, posicion_id, tipo_actividad, estado, descripcion,
  //            superficie_m2, coste_estimado, fecha_programada,
  //            fecha_inicio, fecha_fin, segmentos (JSON-encoded string)
}
```

### 3.2 `SegmentoEntity`

```dart
// Enum TipoInstalacion
enum TipoInstalacion {
  concentrada,
  lineal;
  static TipoInstalacion fromString(String? s) =>
    s?.toLowerCase() == 'concentrada'
      ? TipoInstalacion.concentrada
      : TipoInstalacion.lineal;
}

class SegmentoEntity {
  int? id;
  int ctId;
  String? nombre;
  String? traza;
  TipoInstalacion tipoInstalacion;
  double? pkInicio;
  double? pkFin;
  double? latInicio;
  double? lngInicio;
  double? latFin;
  double? lngFin;
  List<LatLng> ubicacionGis;       // Puntos del segmento en el mapa

  // Computed
  double get longitud { /* suma de distancias haversine entre puntos */ }
  double get longitudKm => longitud / 1000;
  String get displayName => '${nombre ?? ''} - ${traza ?? ''}';
  Map<String, dynamic> get ubicacionGisAsGeoJSON => {
    'type': 'LineString',
    'coordinates': ubicacionGis.map((p) => [p.longitude, p.latitude]).toList(),
  };

  // JSON keys: id, ct_id, nombre, traza, tipo_instalacion,
  //            pk_inicio, pk_fin, lat_inicio, lng_inicio,
  //            lat_fin, lng_fin, ubicacion_gis (GeoJSON LineString string)
  // IMPORTANTE: GeoJSON usa [lng, lat], LatLng usa (lat, lng) → invertir al parsear
}
```

### 3.3 `ImagenSegmentoEntity` (nueva, solo mobile)

```dart
// Entidad para fotos capturadas en campo, asociadas a segmentos
class ImagenSegmentoEntity {
  String localId;          // UUID local (antes de subir)
  int? remoteId;           // ID del servidor (tras subir)
  int actividadId;
  int? segmentoId;         // Segmento al que pertenece (nullable)
  String localPath;        // Ruta local del archivo
  String? remoteUrl;       // URL del servidor (tras subir)
  TipoFoto tipoFoto;       // antes | despues
  DateTime capturedAt;
  double? latitude;
  double? longitude;
  SyncStatus syncStatus;   // pending | uploading | uploaded | error

  enum TipoFoto { antes, despues }
  enum SyncStatus { pending, uploading, uploaded, error }
}
```

---

## 4. API Endpoints

Base URL: `https://enagastool.helireport.com`

> **Autenticación**: Cada request debe incluir headers HMAC-SHA256:
> - `x-flutter-signature`: `HMAC-SHA256(secret, method+path+timestamp+nonce)`
> - `x-flutter-timestamp`: Unix timestamp en segundos
> - `x-flutter-nonce`: UUID aleatorio
> - `Authorization: Bearer {token}` (JWT del login)

### 4.1 Autenticación

| Método | URL | Body | Respuesta |
|--------|-----|------|-----------|
| POST | `/users/login` | `{"usuario": str, "password": str}` | `{"token": str, "usuario": {...}}` |

### 4.2 Actividades

| Método | URL | Descripción |
|--------|-----|-------------|
| GET | `/actividades/bycts/{cts_csv}` | Listar actividades por CTs (ej: "CT001,CT002") |
| GET | `/actividades/byid/{id}` | Obtener actividad por ID |
| GET | `/actividades/operador/{operadorId}/{cts_csv}` | Actividades asignadas a un operador |
| GET | `/actividades/estado/{estado}/{cts_csv}` | Filtrar por estado ("propuesta", "validada", "ejecucion"...) |
| GET | `/actividades/campana/{campana}/{cts_csv}` | Filtrar por campaña |
| POST | `/actividades/update/{id}` | Actualizar estado/datos de una actividad |
| POST | `/actividades/cloud/save` | Guardar actividad con datos de campo |

**Response shape para listas**:
```json
{
  "data": [
    {
      "id": 1,
      "posicion_id": 42,
      "tipo_actividad": "desherbaje_selectivo",
      "estado": "validada",
      "descripcion": "Desherbaje tramo norte",
      "superficie_m2": 1250.5,
      "coste_estimado": 3200.0,
      "fecha_programada": "2025-04-15T00:00:00Z",
      "fecha_inicio": "2025-04-15T08:00:00Z",
      "fecha_fin": "2025-04-15T17:00:00Z",
      "segmentos": "[{...SegmentoEntity.toJson()...}]"
    }
  ],
  "success": true
}
```

### 4.3 Upload de imágenes

| Método | URL | Descripción |
|--------|-----|-------------|
| POST | `/operador/additem` | Upload de imagen como multipart/form-data |

**Request body** (`multipart/form-data`):
```
file: <bytes>                          (campo del archivo)
fileNameOriginal: "foto_001.jpg"
description: "Antes del trabajo"
tipo: "imagen"
tipovigilancia: "VH"
usuariologged: "operador01"
idusuariologged: "42"
actividadId: "1"                       # ID de la actividad
segmentoId: "15"                       # ID del segmento (opcional)
tipoFoto: "antes"                      # "antes" | "despues"
```

**MIME types soportados**: `image/jpeg`, `image/png`, `image/heic`

**Detección de MIME por magic bytes**:
- HEIC: bytes[4..7] == `ftyp`
- JPEG: bytes[0..1] == `0xFF 0xD8`
- PNG: bytes[0..3] == `0x89 0x50 0x4E 0x47`

---

## 5. Diseño de Pantallas

### Tema Global (AppTheme)

```dart
// Colores del módulo desherbaje (consistentes con webapp)
class AppColors {
  // Primario módulo
  static const moduleGreen      = Color(0xFF388E3C); // green.shade700
  static const moduleGreenLight = Color(0xFFF1F8E9); // green.shade50
  static const moduleGreenDark  = Color(0xFF1B5E20); // green.shade900
  static const moduleGreenText  = Color(0xFF1B5E20); // green.shade800

  // Estados actividad (accent / barra lateral)
  static const estadoPropuesta  = Color(0xFF78909C);
  static const estadoValidada   = Color(0xFF1976D2);
  static const estadoEjecucion  = Color(0xFFF57C00);
  static const estadoFinalizada = Color(0xFF388E3C);
  static const estadoCerrada    = Color(0xFF546E7A);

  // Backgrounds de estado (relleno de cards)
  static const bgPropuesta  = Color(0xFFECEFF1);
  static const bgValidada   = Color(0xFFE3F2FD);
  static const bgEjecucion  = Color(0xFFFFF3E0);
  static const bgFinalizada = Color(0xFFE8F5E9);
  static const bgCerrada    = Color(0xFFECEFF1);

  // Generales
  static const surface      = Colors.white;
  static const background   = Color(0xFFF5F5F5);
  static const textPrimary  = Color(0xFF212121);
  static const textSecondary = Color(0xFF757575);
  static const divider      = Color(0xFFBDBDBD);

  static Color accentForEstado(EstadoActividad e) => switch (e) {
    EstadoActividad.propuesta  => estadoPropuesta,
    EstadoActividad.ejecucion  => estadoEjecucion,
  };

  static Color bgForEstado(EstadoActividad e) => switch (e) {
    EstadoActividad.propuesta  => bgPropuesta,
    EstadoActividad.ejecucion  => bgEjecucion,
  };
}

// Tipografía
class AppTextStyles {
  static const headline   = TextStyle(fontSize: 20, fontWeight: FontWeight.w700);
  static const title      = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
  static const subtitle   = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
  static const body       = TextStyle(fontSize: 14);
  static const caption    = TextStyle(fontSize: 12);
  static const badge      = TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4, color: Colors.white);
  static const metric     = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const metricSmall = TextStyle(fontSize: 11, fontStyle: FontStyle.italic);
}

// Spacing
class AppSpacing {
  static const xs  = 4.0;
  static const sm  = 8.0;
  static const md  = 12.0;
  static const lg  = 16.0;
  static const xl  = 24.0;
  static const xxl = 32.0;
}
```

---

### P1: Login

**Archivo**: `presentation/auth/login_page.dart`

```
Scaffold (backgroundColor: Color(0xFFF1F8E9) — verde muy claro)
  body: SafeArea
    Center
      SingleChildScrollView
        Padding(horizontal: 32)
          Column
            [Logo] Image.asset('assets/logo.png', height: 80)
            SizedBox(height: 32)
            [Título] Text("Helireport Desherbaje")
                     fontSize:24, fontWeight:bold, color: green.shade800
            [Subtítulo] Text("Operadores de campo")
                        fontSize:14, color: grey.shade600
            SizedBox(height: 40)
            [Campo usuario] TextFormField
                            labelText: 'Usuario', prefixIcon: Icons.person_outline
                            border: OutlineInputBorder(radius:12)
            SizedBox(height: 16)
            [Campo password] TextFormField
                             labelText: 'Contraseña', prefixIcon: Icons.lock_outline
                             obscureText: true, suffixIcon: toggle visibility
                             border: OutlineInputBorder(radius:12)
            SizedBox(height: 32)
            [Botón login] ElevatedButton (fullWidth, height:52, radius:12)
                          backgroundColor: green.shade700
                          child: Text('Iniciar sesión', fontSize:16, bold)
                          onPressed: controller.login()
            [Loading] LinearProgressIndicator debajo del botón (Obx)
            [Error] Text en rojo (Obx, solo si hay error)
```

**Comportamiento**:
- Al confirmar login exitoso → navegar a `/actividades`
- Guardar token en `flutter_secure_storage`
- El campo usuario recuerda el último valor con `shared_preferences`

---

### P2: Lista de Actividades

**Archivo**: `presentation/actividades/actividades_list_page.dart`

```
Scaffold
  appBar: AppBar
    backgroundColor: green.shade50
    elevation: 0
    bottom: Border(bottom: BorderSide(green.shade200, 2))
    leading: [icono hoja verde]
    title: Column
             Text("Mis Actividades", fontSize:18, bold, color:green.shade800)
             Text("${actividades.length} actividades", fontSize:12, grey)
    actions:
      [Filtro estado] IconButton(Icons.filter_list) → BottomSheet de filtros
      [Actualizar]    IconButton(Icons.refresh)     → controller.reload()
      [Logout]        IconButton(Icons.logout)

  body: Column
    [Chips de filtro] SingleChildScrollView(horizontal)
                      Wrap de FilterChip por cada EstadoActividad
                      selectedColor: accentColor.withOpacity(0.2)
                      checkmarkColor: accentColor
    [Lista] Expanded
            Obx → ListView.builder(
              itemCount: actividades.length,
              itemBuilder: (_,i) => ActividadCard(actividad: actividades[i])
            )
            Estado vacío: Column(Icons.work_off + "Sin actividades")
            Loading: Center(CircularProgressIndicator verde)
```

**`ActividadCard` widget** (diseño idéntico a webapp):

```
Card (margin: sym horizontal:12 vertical:6, elevation: 1, radius:10)
  InkWell(onTap: → detalle, radius:10)
    IntrinsicHeight
      Row(crossAxis: stretch)
        [Barra lateral 4px] Container(color: accentColor, radius topleft/bottomleft 10)
        [Contenido] Expanded → Padding(10,10,12,10)
          Column
            Row  ← Cabecera
              [Badge estado] Container(radius:20, bg:accentColor)
                             Text(estado.etiqueta.toUpperCase(), style:badge)
              Spacer
              [Tipo] Text(tipoActividad.etiqueta, fontSize:10, color:grey)
              [Flecha] Icon(Icons.chevron_right, grey)
            SizedBox(8)
            [Descripción] Text(descripcion, fontSize:14, bold, max:2 líneas)
            SizedBox(4)
            [Segmentos] Row(icon:Icons.route_outlined 12px + "${segmentos.length} segmentos")
            Divider(grey.shade300)
            Row  ← Métricas
              _MetricChip(Icons.straighten, "${longitud.toFixed(0)} m")
              SizedBox(8)
              _MetricChip(Icons.square_foot, "${superficieM2.toFixed(0)} m²")
            Divider(grey.shade300)
            Row  ← Fechas
              _DateChip(Icons.event, fechaInicio)
              Spacer
              [Estado badge grande] Container(radius:6, bg:bgColor)
                                   Text(estado.etiqueta, color:accentColor, bold)
```

**`_MetricChip`**:
```
Row: Icon(size:13, color:blueGrey.shade400) + SizedBox(4) + Text(value, fontSize:12, w600)
```

**`_DateChip`**:
```
Row: Icon(size:12, color:grey.shade500) + SizedBox(3) + Text("dd/MM/yyyy", fontSize:11)
```

---

### P3: Detalle de Actividad + Mapa

**Archivo**: `presentation/detalle/segmento_detalle_page.dart`

Layout: `Column` — sección info fija en la parte superior (35% altura), mapa abajo (65%), panel de segmentos como `DraggableScrollableSheet` desde abajo.

```
Scaffold
  appBar: AppBar
    backgroundColor: accentColor para el estado
    title: Text("#${actividad.id} — ${actividad.tipoActividad.etiqueta}")
    actions:
      [Fotos] IconButton(Icons.camera_alt) → ir a pantalla de captura
      [Estado] PopupMenuButton → cambiar estado (propuesta→validada→ejecucion→finalizada)

  body: Stack
    [Mapa] Expanded
           FlutterMap
             TileLayer: PNOA WMTS (mismo que webapp)
               urlTemplate: 'https://www.ign.es/wmts/pnoa-ma?...'
               headers: {'User-Agent': 'helireport-desherbaje'}
               tileProvider: CancellableNetworkTileProvider()
             PolylineLayer:
               polylines: segmentos.map((s) → Polyline(
                 points: s.ubicacionGis,
                 color: accentColor,        ← color del estado de la actividad
                 strokeWidth: 5.0,
                 borderColor: Colors.white,
                 borderStrokeWidth: 1.5,
               ))
             MarkerLayer: marcador en punto de inicio de cada segmento
               widget: Container(radius:12, color:accentColor) con índice del segmento
             MapCompass.cupertino()
             ZoomButtons: botones + y - esquina superior derecha

    [DraggableScrollableSheet] initial:0.25, min:0.1, max:0.6
      decoration: BoxDecoration(white, radius topLeft/topRight:20, shadow)
      Column:
        [Handle] Container(60x4, grey.shade300, margin:12)
        [Header] Padding(12)
                 Row: Text("${segmentos.length} segmentos", bold 16)
                      + Spacer
                      + ElevatedButton.icon(Icons.camera_alt, "Añadir fotos",
                          bg:accentColor)
        Divider
        [Lista segmentos] ListView.separated
                          itemBuilder: SegmentoListItem(segmento, index, onTap)
```

**`SegmentoListItem`**:
```
ListTile
  leading: CircleAvatar(radius:16, bg:accentColor.withOpacity(0.15))
            Text("${index+1}", color:accentColor, bold)
  title: Text(segmento.displayName, fontSize:13, bold)
  subtitle: Text("${segmento.longitudKm.toFixed(2)} km · ${segmento.squareMeters.toFixed(0)} m²",
                 fontSize:11, color:grey)
  trailing: Row(mainSize:min)
              [Badge fotos] si hay fotos → Container(radius:10, green)
                            Text("${fotoCount}", color:white, fontSize:9)
              Icon(Icons.chevron_right)
  onTap: centrar mapa en segmento + abrir fotos del segmento
```

**Comportamiento del mapa**:
- Al cargar: calcular bounds de todos los segmentos y hacer `fitCamera(bounds, padding:EdgeInsets.all(50))`
- Al tap en `SegmentoListItem`: `fitCamera(bounds del segmento, padding:80)`
- Polylines con `hitValue` para detectar tap directo en mapa
- Al tap en polyline: resaltar en naranja (`strokeWidth: 8`) y hacer scroll al item en la lista

---

### P4: Captura de Imágenes

**Archivo**: `presentation/fotos/captura_fotos_page.dart`

```
Scaffold
  appBar: AppBar
    title: Text("Fotos — Actividad #${actividad.id}")
    backgroundColor: green.shade700, foreground: white

  body: Column
    [Selector tipo foto] Container(bg:grey.shade100, padding:12)
                         SegmentedButton<TipoFoto>
                           segments: [
                             ButtonSegment(TipoFoto.antes,  label:"Antes",  icon:Icons.camera_enhance)
                             ButtonSegment(TipoFoto.despues, label:"Después", icon:Icons.check_circle)
                           ]
                           selectedStyle: green filled

    [Selector segmento] si actividad tiene >1 segmento:
                         HorizontalScrollable de ChoiceChip por cada segmento
                         ninguno seleccionado = "toda la actividad"

    [Grid de fotos] Expanded
                    Obx → GridView.builder(crossAxisCount:3, spacing:2)
                      [Foto existente] Stack
                                       CachedNetworkImage o Image.file
                                       Positioned(top:4,right:4): IconButton borrar (rojo)
                                       Positioned(bottom:4,left:4): Chip tipo (antes/despues)
                      [Botón añadir]   Container(border dashed grey, radius:8)
                                       Column: Icon(Icons.add_a_photo, 32, grey)
                                               Text("Añadir foto", 12, grey)
                                       onTap: _showPhotoSourceDialog()

    [Barra inferior] SafeArea
                     Container(bg:white, border top grey, padding:12)
                     Row:
                       Column: Text("${pendientes} por subir", 12, orange)
                               Text("${subidas} subidas", 12, green)
                       Spacer
                       ElevatedButton.icon(
                         icon: Icons.cloud_upload,
                         label: "Subir ${pendientes} fotos",
                         onPressed: controller.uploadPending(),
                         style: green, disabled si pendientes==0
                       )
```

**Diálogo de fuente de foto** (bottom sheet):
```
showModalBottomSheet → Column(mainSize:min, padding:16)
  Text("Añadir foto", bold 18)
  SizedBox(16)
  ListTile(Icons.camera_alt, "Cámara", onTap: _fromCamera())
  ListTile(Icons.photo_library, "Galería", onTap: _fromGallery())
  SizedBox(8)
```

**Vista previa antes de confirmar**:
```
Dialog → Column
  Image(localFile, fit:cover, height:300)
  Row(padding:16):
    SegmentedButton<TipoFoto> (antes/despues)
    DropdownButton<SegmentoEntity?> (segmento)
  Row(botones): TextButton("Descartar") + ElevatedButton("Añadir", green)
```

**Progress de upload**:
```
Obx → si isUploading: LinearProgressIndicator(value: progress, color:green)
                       Text("Subiendo ${current}/${total}...")
```

---

## 6. Flujos de Usuario Completos

### Flujo principal
```
1. LOGIN
   └─ Introducir usuario/password
   └─ POST /users/login
   └─ Guardar JWT en secure storage
   └─ Navegar a /actividades

2. LISTA DE ACTIVIDADES
   └─ GET /actividades/operador/{userId}/{cts}
   └─ Mostrar lista filtrada (solo ejecucion + validada por defecto)
   └─ Filtros: por estado, por fecha
   └─ Tap card → DETALLE

3. DETALLE + MAPA
   └─ Cargar segmentos de la actividad (ya en ActividadEntity.segmentos)
   └─ Centrar mapa en bounds de todos los segmentos
   └─ Ver métricas: longitud total, superficie m2
   └─ Cambiar estado: validada → ejecucion (indica que ha empezado)
   └─ Tap "Añadir fotos" → CAPTURA

4. CAPTURA DE FOTOS
   └─ Seleccionar tipo: ANTES o DESPUÉS
   └─ Seleccionar segmento (opcional, si hay múltiples)
   └─ Tomar foto con cámara O seleccionar de galería
   └─ Preview + confirmación de tipo/segmento
   └─ Guardar local en ImagenSegmentoEntity (syncStatus: pending)
   └─ Repetir para todas las fotos necesarias

5. UPLOAD
   └─ Tap "Subir N fotos"
   └─ Para cada foto pendiente:
       POST /operador/additem (multipart)
       Actualizar syncStatus: uploading → uploaded / error
   └─ Al completar: marcar actividad como finalizada
   └─ POST /actividades/update/{id} con estado: "finalizada"
```

### Flujo offline
```
Sin conectividad:
  └─ Login: intentar, si falla usar credenciales cacheadas (shared_prefs)
  └─ Actividades: servir desde SQLite local
  └─ Fotos: guardar local, syncStatus: pending
  └─ Al recuperar conectividad: sync automático en background
      └─ ConnectivityService.onConnectivityChanged → triggerSync()
      └─ Iterar fotos pendientes y subir
```

---

## 7. Seguridad — HMAC-SHA256

El backend requiere autenticación por firma HMAC en cada request. Implementar en `ApiSecurityService`:

```dart
class ApiSecurityService {
  static const _secret = 'YOUR_HMAC_SECRET'; // desde AppConfig / env

  static Map<String, String> buildHeaders(
    String method,
    String path,
    String? token,
  ) {
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = const Uuid().v4();
    final payload = '$method$path$timestamp$nonce';
    final hmac = Hmac(sha256, utf8.encode(_secret));
    final signature = hmac.convert(utf8.encode(payload)).toString();

    return {
      'x-flutter-signature': signature,
      'x-flutter-timestamp': timestamp,
      'x-flutter-nonce': nonce,
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }
}
```

---

## 8. Persistencia Local (SQLite)

**Base de datos**: `helireport_desherbaje.db`, versión `1`

### Tabla `actividades`
```sql
CREATE TABLE actividades (
  id              INTEGER PRIMARY KEY,
  posicion_id     INTEGER NOT NULL DEFAULT 0,
  tipo_actividad  TEXT NOT NULL DEFAULT 'desherbaje_selectivo',
  estado          TEXT NOT NULL DEFAULT 'propuesta',
  descripcion     TEXT NOT NULL DEFAULT '',
  superficie_m2   REAL NOT NULL DEFAULT 0.0,
  coste_estimado  REAL NOT NULL DEFAULT 0.0,
  fecha_programada TEXT,
  fecha_inicio    TEXT,
  fecha_fin       TEXT,
  segmentos_json  TEXT,              -- JSON array de SegmentoEntity
  synced_at       TEXT,
  needs_sync      INTEGER NOT NULL DEFAULT 0
);
```

### Tabla `imagenes_actividad`
```sql
CREATE TABLE imagenes_actividad (
  local_id        TEXT PRIMARY KEY,  -- UUID
  remote_id       INTEGER,
  actividad_id    INTEGER NOT NULL,
  segmento_id     INTEGER,
  local_path      TEXT NOT NULL,
  remote_url      TEXT,
  tipo_foto       TEXT NOT NULL,     -- 'antes' | 'despues'
  captured_at     TEXT NOT NULL,
  latitude        REAL,
  longitude       REAL,
  sync_status     TEXT NOT NULL DEFAULT 'pending',
  created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_imagenes_actividad ON imagenes_actividad(actividad_id);
CREATE INDEX idx_imagenes_sync ON imagenes_actividad(sync_status);
```

---

## 9. Patrones de Arquitectura

### GetX Controller pattern
```dart
// Patrón obligatorio en toda la app
class SegmentosListController extends GetxController {
  // Estado reactivo
  final actividades = <ActividadEntity>[].obs;
  final isLoading = false.obs;
  final selectedEstado = Rx<EstadoActividad?>(null);
  final error = Rx<String?>(null);

  @override
  void onInit() {
    super.onInit();
    loadActividades();
  }

  Future<void> loadActividades() async {
    isLoading.value = true;
    error.value = null;
    try {
      final result = await _useCase.execute();
      actividades.assignAll(result);
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }
}
```

### Offline-First Factory
```dart
abstract class SegmentoDataProvider {
  Future<List<ActividadEntity>> getByOperador(int operadorId, List<String> cts);
  Future<ActividadEntity?> getById(int id);
  Future<bool> updateEstado(int id, EstadoActividad estado);
}

class SegmentoDataProviderFactory {
  static SegmentoDataProvider create() {
    final isOnline = Get.find<ConnectivityService>().isConnected;
    return isOnline
      ? SegmentoDataProviderOnline()
      : SegmentoDataProviderOffline();
  }
}
```

### Routing
```dart
// Rutas de la app
class AppRoutes {
  static const login      = '/login';
  static const actividades = '/actividades';
  static const detalle    = '/actividades/detalle';
  static const fotos      = '/actividades/fotos';
}

// GetPage list en main_app.dart
final pages = [
  GetPage(name: AppRoutes.login,       page: () => LoginPage(),
                                        binding: LoginBinding()),
  GetPage(name: AppRoutes.actividades, page: () => SegmentosListPage(),
                                        binding: SegmentosListBinding(),
                                        middlewares: [AuthMiddleware()]),
  GetPage(name: AppRoutes.detalle,     page: () => SegmentoDetallePage(),
                                        binding: ActividadDetalleBinding(),
                                        middlewares: [AuthMiddleware()]),
  GetPage(name: AppRoutes.fotos,       page: () => CapturaFotosPage(),
                                        binding: CapturaFotosBinding(),
                                        middlewares: [AuthMiddleware()]),
];
```

---

## 10. Configuración de Entornos

```dart
class AppConfig {
  static bool get isProduction => !_isTest;
  static bool get _isTest =>
    const bool.fromEnvironment('ENV', defaultValue: false) == false
      ? (Uri.base.host.contains('localhost') || Uri.base.host.contains('127.0.0.1'))
      : true;

  static String get baseUrl =>
    isProduction
      ? 'https://enagastool.helireport.com'
      : 'http://10.0.2.2:8080';  // Android emulator → localhost
}
```

---

## 11. Permisos Requeridos

### Android (`AndroidManifest.xml`)
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
                 android:maxSdkVersion="28"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

### iOS (`Info.plist`)
```xml
<key>NSCameraUsageDescription</key>
<string>Necesario para capturar fotos de los trabajos de desherbaje</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Necesario para seleccionar fotos de los trabajos</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Necesario para geolocalizar las fotos de los trabajos</string>
```

---

## 12. Comandos de Desarrollo

```bash
# Crear el proyecto
flutter create \
  --org com.leulit.enagas \
  --project-name helireport_desherbaje \
  --platforms android,ios \
  .

# Instalar dependencias
flutter pub get

# Ejecutar en Android emulator
flutter run -d android

# Ejecutar en iOS simulator
flutter run -d ios

# Build Android release
flutter build apk --release

# Build iOS release
flutter build ipa --no-codesign

# Analizar código
flutter analyze

# Tests
flutter test
```

---

## 13. Checklist de Implementación

### Fase 1 — Base
- [ ] `flutter create` y estructura de carpetas
- [ ] `AppTheme` con colores del módulo desherbaje
- [ ] `AppConfig`, `AppDI`, `AppRouter`
- [ ] `ApiSecurityService` (HMAC-SHA256)
- [ ] `NetworkService` (Dio + interceptors)
- [ ] `LocalDatabase` (SQLite, tablas actividades + imagenes)
- [ ] `ConnectivityService`

### Fase 2 — Autenticación
- [ ] `LoginPage` + `LoginController`
- [ ] `AuthRepository` + `AuthDataProvider`
- [ ] `AuthMiddleware` (redirect a login si no autenticado)
- [ ] `SecureStorage` para JWT

### Fase 3 — Actividades
- [ ] `SegmentoDataProvider` (abstract + online + offline + factory)
- [ ] `ActividadRepository`
- [ ] `GetSegmentosUseCase`
- [ ] `SegmentosListPage` + cards
- [ ] `SegmentoDetallePage` + mapa con polylines
- [ ] Cambio de estado de actividad

### Fase 4 — Fotos
- [ ] `ImagenSegmentoEntity` + tabla SQLite
- [ ] `CapturaFotosPage` (grid + botones antes/después + segmento selector)
- [ ] `ImageUploadProvider` (POST `/operador/additem`)
- [ ] Upload con progreso + manejo de errores
- [ ] Sync automático al recuperar conectividad

### Fase 5 — Pulido
- [ ] Empty states, error states, loading states en todas las pantallas
- [ ] Confirmación antes de cambiar estado a "finalizada"
- [ ] Badge en lista de actividades mostrando fotos pendientes de subir
- [ ] Pull-to-refresh en lista de actividades
- [ ] Tests unitarios de repositories y use cases
