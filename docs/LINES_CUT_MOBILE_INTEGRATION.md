# Líneas de Corte — Guía de implementación para App Móvil

> Objetivo: portar al proyecto móvil la misma funcionalidad de **detección y
> extracción de segmentos entre dos líneas de corte** que se ejecuta en la webapp
> (`lib/views/desherbajemain/widgets/layers/lines_cut_layer.dart` +
> `lines_cut_layer_controller.dart`).
>
> Esta guía es autocontenida: incluye algoritmo, contrato de estado, código
> portable (sin dependencias de ActionManager ni de `DesherbajeController`) y
> los puntos exactos donde el equipo móvil debe conectar con su propio mapa.

---

## 1. Qué hace la funcionalidad

El usuario dibuja **dos líneas rectas** (cada una con 2 puntos) sobre el mapa,
encima de la capa de gasoductos. El sistema:

1. Valida que las dos líneas **no se crucen entre sí**.
2. Recorre las polylines de gasoductos visibles en el viewport y, para cada una,
   calcula sus intersecciones con L1 y L2.
3. Extrae el **tramo** de la polyline que queda "entre" las dos líneas de corte,
   aplicando estas reglas:

| Caso | Regla |
|---|---|
| La polyline cruza L1 **y** L2 | Se queda con el tramo entre ambas intersecciones. |
| La polyline cruza **solo** L1 | Se queda con la mitad que mira hacia L2. |
| La polyline cruza **solo** L2 | Se queda con la mitad que mira hacia L1. |
| La polyline no cruza ninguna | Se descarta (no participa en el corte). |

4. Elimina solapamientos con segmentos ya existentes en el backend.
5. Muestra un diálogo para capturar descripción / tipo de actividad / estado.
6. Emite los `PolylineSegment` resultantes para que la capa consumidora los
   pinte y los guarde como `SegmentoEntity`.

Estado visual durante la operación: Línea 1 verde, Línea 2 morada, marcadores
arrastrables numerados (1,2) por línea, warning rojo si las líneas se
intersectan.

---

## 2. Arquitectura lógica (independiente del framework de estado)

```
        ┌─────────────────────────────────────────────┐
        │           MAPA (flutter_map)                │
        │  ┌──────────────────────────────────────┐   │
 tap ───▶  │  Capa de gasoductos (polylines)      │   │
 zoom ──▶  │  LinesCutLayer (esta funcionalidad)  │   │
        │  └──────────────────────────────────────┘   │
        └──────────────┬──────────────────────────────┘
                       │ onTap / onZoom / polylinesVisibles
                       ▼
        ┌──────────────────────────────────────────────┐
        │         LinesCutController                   │
        │  - state: line1Points, line2Points           │
        │           activeLine, canCut, cutStateOn     │
        │           zoomOk, hasIntersectionError       │
        │  - addPoint / updatePoint / clear*           │
        │  - _validateIntersection  (segmentos 1 vs 2) │
        │  - extractAndApplyCut                        │
        │     └─▶ _extractPolylineSegmentsBetweenLines │
        │            └─▶ _getLineIntersection          │
        │            └─▶ _keepHalfTowardOther          │
        └──────────────┬───────────────────────────────┘
                       │ List<PolylineSegment>
                       ▼
        ┌──────────────────────────────────────────────┐
        │  ExtractedSegmentsLayer + SegmentoEntity     │
        │  (existente en el proyecto móvil o a portar) │
        └──────────────────────────────────────────────┘
```

El **núcleo matemático** está totalmente desacoplado de GetX y de
ActionManager: se puede extraer a un fichero utilitario y usarlo desde
Provider, Bloc, Riverpod, GetX o cualquier otro patrón.

---

## 3. Fundamento matemático

Todo el código opera sobre `LatLng` tratando `(longitude, latitude)` como
coordenadas cartesianas `(x, y)`. Para distancias cortas (líneas visibles en
pantalla a zoom ≥ 12) la distorsión es despreciable y el resultado es
idéntico al web.

### 3.1 Orientación de tres puntos (determinante)

Usado para decidir si dos segmentos se cruzan:

```
val = (Bx − Ax)·(Cy − By) − (By − Ay)·(Cx − Bx)
  val > 0  → sentido horario
  val < 0  → sentido antihorario
  val ≈ 0  → colineales
```

(En el código la `x` es `longitude` y la `y` es `latitude` — cuidado al
mapear.)

### 3.2 Test de intersección de dos segmentos `A–B` y `C–D`

```
o1 = orientation(A, B, C)
o2 = orientation(A, B, D)
o3 = orientation(C, D, A)
o4 = orientation(C, D, B)

caso general:      o1 ≠ o2  ∧  o3 ≠ o4  ⇒ se intersectan
casos colineales:  un oi == 0 y el punto cae dentro del bbox del otro segmento
```

### 3.3 Punto de intersección (paramétrico)

Dadas dos rectas `P1P2` y `P3P4`:

```
den = (x1 − x2)(y3 − y4) − (y1 − y2)(x3 − x4)
t   = ((x1 − x3)(y3 − y4) − (y1 − y3)(x3 − x4)) / den
u   = −((x1 − x2)(y1 − y3) − (y1 − y2)(x1 − x3)) / den

si 0 ≤ t ≤ 1 ∧ 0 ≤ u ≤ 1  ⇒ hay intersección dentro de ambos segmentos
ix = (x1 + t·(x2 − x1),  y1 + t·(y2 − y1))
```

Si `|den| < 1e-10` las rectas son paralelas o coincidentes → `null`.

### 3.4 Lado del corte (producto cruz con signo)

Para decidir qué mitad de una polyline conservar cuando solo cruza una de
las dos líneas de corte:

```
side(A, B, P) = (Bx − Ax)·(Py − Ay) − (By − Ay)·(Px − Ax)
  > 0 → P a la izquierda del vector A→B
  < 0 → P a la derecha
```

Se compara el lado del **punto medio de la otra línea de corte** con el
lado del **punto siguiente a la intersección** dentro de la polyline. Si
coinciden → el tramo "de la intersección hacia adelante" es el bueno; si
no → el bueno es el tramo "desde el inicio hasta la intersección".

---

## 4. Contrato de estado (state machine)

La capa se rige por cuatro flags reactivas y dos listas de puntos:

| Campo | Tipo | Significado |
|---|---|---|
| `cutStateOn` | `bool` | La feature está activa (desde el panel/botón de modo "líneas de corte"). |
| `zoomOk` | `bool` | `map.camera.zoom > 12`. Si no, la capa no se renderiza aunque esté activa. |
| `canCut` | `bool` | El usuario ha pulsado "Líneas de corte" y está realmente dibujando. |
| `activeLine` | `int (1|2)` | Qué línea recibe el próximo tap. |
| `line1Points` / `line2Points` | `List<LatLng>` (max 2 cada una) | Geometría de las líneas. |
| `hasIntersectionError` | `bool` | Las dos líneas se cruzan → estado inválido. |
| `areLinesCutReady` | `bool` | Derivado: `len(L1)==2 ∧ len(L2)==2 ∧ !intersectionError`. Habilita "Aplicar corte". |

Transiciones relevantes:

- `addPoint(p)`: añade `p` a la línea activa. Si la línea 1 se completa, cambia
  `activeLine` a 2. Si ambas se completan, lanza `_validateIntersection()`.
- `updatePoint(line, index, newPos)`: actualiza un punto por arrastre y
  revalida intersección.
- `clearLine(n)` / `clearAll()`: borra y resetea `hasIntersectionError`.
- `updStatus(false)`: al desactivar la feature, `canCut = false` + `clearAll()`.

La capa se pinta solo cuando `cutStateOn && zoomOk`.

---

## 5. Código portable (copy-paste friendly)

Todo lo siguiente es Dart puro sobre `flutter_map` + `latlong2`. **No hay
dependencia alguna de GetX, ActionManager ni del `DesherbajeController`**: el
equipo móvil lo puede envolver en su patrón de estado preferido.

### 5.1 `lines_cut_math.dart`

```dart
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Devuelve true si los segmentos [p1-q1] y [p2-q2] se intersectan.
bool doSegmentsIntersect(LatLng p1, LatLng q1, LatLng p2, LatLng q2) {
  int orientation(LatLng a, LatLng b, LatLng c) {
    final val = (b.latitude - a.latitude) * (c.longitude - b.longitude) -
                (b.longitude - a.longitude) * (c.latitude - b.latitude);
    if (val.abs() < 1e-7) return 0;
    return val > 0 ? 1 : 2;
  }

  bool onSegment(LatLng p, LatLng q, LatLng r) =>
      q.latitude  <= math.max(p.latitude,  r.latitude)  &&
      q.latitude  >= math.min(p.latitude,  r.latitude)  &&
      q.longitude <= math.max(p.longitude, r.longitude) &&
      q.longitude >= math.min(p.longitude, r.longitude);

  final o1 = orientation(p1, q1, p2);
  final o2 = orientation(p1, q1, q2);
  final o3 = orientation(p2, q2, p1);
  final o4 = orientation(p2, q2, q1);

  if (o1 != o2 && o3 != o4) return true;
  if (o1 == 0 && onSegment(p1, p2, q1)) return true;
  if (o2 == 0 && onSegment(p1, q2, q1)) return true;
  if (o3 == 0 && onSegment(p2, p1, q2)) return true;
  if (o4 == 0 && onSegment(p2, q1, q2)) return true;
  return false;
}

/// Punto de intersección entre dos segmentos, o null si no existe dentro
/// de ambos segmentos o si son paralelos.
LatLng? getSegmentIntersection(LatLng p1, LatLng p2, LatLng p3, LatLng p4) {
  final x1 = p1.longitude, y1 = p1.latitude;
  final x2 = p2.longitude, y2 = p2.latitude;
  final x3 = p3.longitude, y3 = p3.latitude;
  final x4 = p4.longitude, y4 = p4.latitude;

  final den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
  if (den.abs() < 1e-10) return null;

  final t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den;
  final u = -((x1 - x2) * (y1 - y3) - (y1 - y2) * (x1 - x3)) / den;

  if (t < 0 || t > 1 || u < 0 || u > 1) return null;
  return LatLng(y1 + t * (y2 - y1), x1 + t * (x2 - x1));
}

/// Área con signo: >0 si P está a la izquierda del vector A→B, <0 a la derecha.
double sideOfLine(LatLng a, LatLng b, LatLng p) =>
    (b.longitude - a.longitude) * (p.latitude  - a.latitude) -
    (b.latitude  - a.latitude)  * (p.longitude - a.longitude);
```

### 5.2 `polyline_segment.dart`

Modelo de salida. En la webapp vive en
`lib/core/utils/polyline_polygon_intersector.dart`. Versión mínima que el
móvil puede usar directamente:

```dart
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class PolylineSegment {
  final int id;
  final List<LatLng> points;
  final Polyline originalPolyline;   // para recuperar metadatos (hitValue, ct, name…)

  // Campos que rellena el diálogo posterior al corte
  String description = '';
  // Sustituir por los enums reales del proyecto móvil si existen.
  // En web: TipoActividad.desherbajeSelectivo, EstadoActividad.propuesta.
  Object? tipoActividad;
  Object? estado;

  PolylineSegment({
    required this.id,
    required this.points,
    required this.originalPolyline,
  });

  double get lengthMeters {
    if (points.length < 2) return 0;
    const d = Distance();
    double total = 0;
    for (var i = 0; i < points.length - 1; i++) {
      total += d.as(LengthUnit.Meter, points[i], points[i + 1]);
    }
    return total;
  }
}
```

> En la webapp, `PolylineSegment` además extrae `ctId`, `name` y `traza`
> desde `polyline.hitValue`. Si el móvil usa el mismo `hitValue`
> (`PolylineHitData` con campos `ct` y `name`), conviene copiar los
> helpers `_extractCtIdFromPolyline`, `_extractNameFromPolyline` y
> `_extractTrazaFromPolyline` tal cual de
> `lib/core/utils/polyline_polygon_intersector.dart` (líneas 346–407).

### 5.3 `lines_cut_engine.dart` — el motor de extracción

Esta es la función clave. **No toca framework de estado**: recibe las dos
líneas y la lista de polylines candidatas, devuelve los segmentos.

```dart
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'lines_cut_math.dart';
import 'polyline_segment.dart';

List<PolylineSegment> extractSegmentsBetweenCutLines({
  required List<LatLng> line1Points,   // length == 2
  required List<LatLng> line2Points,   // length == 2
  required List<Polyline> visiblePolylines,
}) {
  if (line1Points.length != 2 || line2Points.length != 2) return const [];

  final l1s = line1Points[0], l1e = line1Points[1];
  final l2s = line2Points[0], l2e = line2Points[1];
  final segments = <PolylineSegment>[];

  for (final polyline in visiblePolylines) {
    final pts = polyline.points;
    if (pts.length < 2) continue;

    LatLng? ix1; int? ix1Seg;
    LatLng? ix2; int? ix2Seg;

    for (var i = 0; i < pts.length - 1; i++) {
      ix1 ??= () {
        final x = getSegmentIntersection(pts[i], pts[i + 1], l1s, l1e);
        if (x != null) ix1Seg = i;
        return x;
      }();
      ix2 ??= () {
        final x = getSegmentIntersection(pts[i], pts[i + 1], l2s, l2e);
        if (x != null) ix2Seg = i;
        return x;
      }();
      if (ix1 != null && ix2 != null) break;
    }

    if (ix1 == null && ix2 == null) continue; // no cruza ninguna → descartar

    final List<LatLng> segPts;
    if (ix1 != null && ix2 != null) {
      // Caso 1: cruza ambas
      final startSeg = math.min(ix1Seg!, ix2Seg!);
      final endSeg   = math.max(ix1Seg!, ix2Seg!);
      final startIx  = ix1Seg! < ix2Seg! ? ix1 : ix2;
      final endIx    = ix1Seg! < ix2Seg! ? ix2 : ix1;

      segPts = [startIx, for (var i = startSeg + 1; i <= endSeg; i++) pts[i], endIx];
    } else if (ix1 != null) {
      // Caso 2: solo L1 → conservar mitad hacia L2
      segPts = _keepHalfTowardOther(pts, ix1, ix1Seg!, l1s, l1e, l2s, l2e);
    } else {
      // Caso 3: solo L2 → conservar mitad hacia L1
      segPts = _keepHalfTowardOther(pts, ix2!, ix2Seg!, l2s, l2e, l1s, l1e);
    }

    if (segPts.length >= 2) {
      segments.add(PolylineSegment(
        id: DateTime.now().microsecondsSinceEpoch,
        points: segPts,
        originalPolyline: polyline,
      ));
    }
  }
  return segments;
}

List<LatLng> _keepHalfTowardOther(
  List<LatLng> pts, LatLng ix, int ixSeg,
  LatLng cls, LatLng cle,   // línea de corte cruzada
  LatLng ols, LatLng ole,   // otra línea (referencia de dirección)
) {
  final refMid = LatLng(
    (ols.latitude  + ole.latitude)  / 2,
    (ols.longitude + ole.longitude) / 2,
  );
  final sideRef  = sideOfLine(cls, cle, refMid);
  final nextIdx  = math.min(ixSeg + 1, pts.length - 1);
  final sideNext = sideOfLine(cls, cle, pts[nextIdx]);

  if ((sideNext >= 0) == (sideRef >= 0)) {
    return [ix, ...pts.sublist(ixSeg + 1)];
  } else {
    return [...pts.sublist(0, ixSeg + 1), ix];
  }
}
```

Complejidad: **O(N·M)** donde `N` = número de polylines visibles y `M` =
promedio de vértices por polyline. Para acotar el coste a viewport, el móvil
debe pasar solo las polylines que están dentro de los bounds actuales del
mapa (eso ya hace la web con `DesherbajeController.polylinesVisibles`).

### 5.4 Controlador — plantilla mínima

Si el móvil usa GetX, puede copiar
`lines_cut_layer_controller.dart` casi tal cual (cambiando la conexión con
ActionManager por su equivalente). Si no, este es el **esqueleto agnóstico**
(usable desde `ChangeNotifier`, Cubit, GetxController, etc.):

```dart
class LinesCutState {
  final List<LatLng> line1Points = [];
  final List<LatLng> line2Points = [];
  int activeLine = 1;            // 1 ó 2
  bool hasIntersectionError = false;
  bool canCut = false;           // modo dibujo activo
  bool cutStateOn = false;       // feature activa
  bool zoomOk = false;           // zoom > 12

  bool get areLinesCutReady =>
      line1Points.length == 2 &&
      line2Points.length == 2 &&
      !hasIntersectionError;

  String get statusMessage {
    if (line1Points.isEmpty)         return 'Marca el primer punto de la Línea 1';
    if (line1Points.length == 1)     return 'Marca el segundo punto de la Línea 1';
    if (line2Points.isEmpty)         return 'Marca el primer punto de la Línea 2';
    if (line2Points.length == 1)     return 'Marca el segundo punto de la Línea 2';
    if (hasIntersectionError)        return '⚠️ Las líneas se intersectan';
    return '✅ Líneas listas para cortar';
  }
}

void addPoint(LinesCutState s, LatLng p) {
  if (!s.canCut) return;
  if (s.activeLine == 1 && s.line1Points.length < 2) {
    s.line1Points.add(p);
    if (s.line1Points.length == 2) s.activeLine = 2;
  } else if (s.activeLine == 2 && s.line2Points.length < 2) {
    s.line2Points.add(p);
  }
  _revalidate(s);
}

void updatePoint(LinesCutState s, int line, int idx, LatLng p) {
  if (line == 1 && idx < s.line1Points.length) s.line1Points[idx] = p;
  if (line == 2 && idx < s.line2Points.length) s.line2Points[idx] = p;
  _revalidate(s);
}

void _revalidate(LinesCutState s) {
  s.hasIntersectionError = s.line1Points.length == 2 && s.line2Points.length == 2 &&
      doSegmentsIntersect(s.line1Points[0], s.line1Points[1],
                          s.line2Points[0], s.line2Points[1]);
}

void clearAll(LinesCutState s) {
  s.line1Points.clear();
  s.line2Points.clear();
  s.activeLine = 1;
  s.hasIntersectionError = false;
}
```

### 5.5 Capa de mapa (widget)

Equivale a `lines_cut_layer.dart`. Lo que **debe renderizar** es:

1. **Botón de modo** (arriba-derecha): "Líneas de corte" ↔ "Finalizar corte".
   Alterna `canCut`. Al pasar a false, `clearAll()`.
2. **Panel de control** (arriba-izquierda, solo si `canCut`): selector de
   línea activa (1 ó 2), botones "Aplicar corte" (habilitado sólo si
   `areLinesCutReady`) y "Limpiar".
3. **2x `PolylineLayer`** — uno por línea, con `strokeWidth` mayor si es la
   activa y borde blanco `1.0`:
   - Línea 1: `Colors.green`
   - Línea 2: `Colors.purple`
4. **`DragMarkers`** (paquete `flutter_map_dragmarker` o equivalente) para los
   hasta 4 marcadores numerados. En web se usa el wrapper interno
   `core/ui/map/dragmarker/drag_markers_layer.dart` — el móvil puede usar
   cualquier implementación de drag markers sobre `flutter_map`.
5. **Warning** central rojo si `hasIntersectionError`.

El layer sólo se muestra cuando `cutStateOn && zoomOk`.

---

## 6. Integración con el mapa del móvil

Tres puntos de conexión que el equipo móvil debe resolver en su
arquitectura:

### 6.1 Captura de taps

En la web se escucha `AppTypedActions.mapTapEvent` y, si `canCut`, se llama
a `addPoint(tap.tapPosition)`. En el móvil basta con conectar
`MapOptions.onTap` → `if (state.canCut) addPoint(latlng)`.

### 6.2 Control de zoom mínimo

En la web se escucha `AppTypedActions.mapZoomEvent` y se hace
`zoomOk = event.camera.zoom > 12`. En el móvil: `MapOptions.onMapEvent` +
filtrar por `MapEvent` que lleven cambio de cámara.

### 6.3 Lista de polylines visibles

El motor necesita una `List<Polyline>` con los gasoductos visibles en el
viewport. En la web lo resuelve el `GasoductosLayerController`, que publica
`polylinesVisibles` en el `DesherbajeController`. El móvil debe exponer
exactamente lo mismo — idealmente sólo las polylines dentro de
`mapController.camera.visibleBounds` para mantener el cost O(N·M) acotado.

Contrato mínimo:

```dart
List<Polyline> getVisibleGasoductoPolylines();
```

---

## 7. Flujo completo (happy path)

```
[UI] pulsa botón "Líneas de corte"
   └─▶ state.canCut = true

[mapa] tap1 → addPoint(p)  → line1Points = [p]
[mapa] tap2 → addPoint(p)  → line1Points = [p1, p2]; activeLine = 2
[mapa] tap3 → addPoint(p)  → line2Points = [p]
[mapa] tap4 → addPoint(p)  → line2Points = [p1, p2]
                              _validateIntersection()
                              hasIntersectionError = false
                              areLinesCutReady = true  → habilita botón "Aplicar"

[UI] pulsa "Aplicar corte"
   └─▶ extractSegmentsBetweenCutLines(line1Points, line2Points,
                                     visiblePolylines)
         → List<PolylineSegment>
   └─▶ remove overlapping con segmentos ya existentes (opcional, ver §8)
   └─▶ abre diálogo captura (descripción, tipoActividad, estado)
   └─▶ aplica los 3 valores a todos los segmentos devueltos
   └─▶ entrega la lista a la capa de ExtractedSegments (o al controlador
        que persiste los SegmentoEntity en backend/offline DB)
   └─▶ clearAll()
```

Si el usuario cancela el diálogo → **NO** se hace `clearAll()`: las líneas
se mantienen en pantalla para que pueda reajustar. Es un detalle importante
de UX replicado del web (`lines_cut_layer_controller.dart:264`).

---

## 8. Filtro de solapamientos con segmentos existentes

En la web, antes de abrir el diálogo, se filtra la lista contra los
segmentos ya guardados:

```dart
final filtered = await DesherbajeTypedActions
    .removeOverlappingWithExisting.dispatchAsync(data: rawSegments);
```

El handler real vive en el `SegmentosPanelController` de la web. En el móvil,
el equipo debe:

1. Obtener del backend o de la DB local los `SegmentoEntity` ya existentes
   para el área visible.
2. Por cada `PolylineSegment` extraído, comprobar si su geometría solapa con
   alguno existente (bounding-box + distancia punto-a-línea al umbral que
   definan, p.ej. `< 2 m`).
3. Descartar los solapados antes de abrir el diálogo.

Si el módulo ya estaba implementado para el flujo de "Dibujar polígono"
(`PolylinePolygonIntersector`), muy probablemente el filtro ya existe y se
puede reutilizar.

---

## 9. Modelo de salida (`SegmentoEntity`)

La web convierte cada `PolylineSegment` a un `SegmentoEntity` con:

```dart
segmento.ubicacionGis = segment.points;
segmento.latInicio    = segment.points.first.latitude;
segmento.lngInicio    = segment.points.first.longitude;
segmento.latFin       = segment.points.last.latitude;   // ⚠️ ver nota
segmento.lngFin       = segment.points.last.longitude;  // ⚠️ ver nota
segmento.ctId         = segment.ctId;
segmento.description  = dialog.descripcion;
segmento.tipoActividad = dialog.tipoActividad;
segmento.estado       = dialog.estado;
```

> ⚠️ **Bug conocido en la web** (`lines_cut_layer_controller.dart:253-257`):
> los campos `latFin`/`lngFin` se están asignando al `first` en lugar de al
> `last`. El móvil debería corregirlo desde el arranque:
> `segment.points.last.latitude` / `.longitude`.

---

## 10. Dependencias necesarias en el `pubspec.yaml` móvil

```yaml
dependencies:
  flutter_map: ^8.2.2
  latlong2: ^0.9.1
  # Drag markers — cualquiera de estos vale; el web usa implementación
  # propia en lib/core/ui/map/dragmarker/
  flutter_map_dragmarker: ^7.0.0   # si decidís usar paquete externo
```

No hace falta `turf` — el motor de líneas de corte no lo usa (a diferencia
del `PolylinePolygonIntersector` para el flujo de polígonos).

---

## 11. Checklist de implementación

- [ ] Portar `lines_cut_math.dart` (§5.1).
- [ ] Crear `PolylineSegment` mínimo o reutilizar el existente si el móvil
      ya tiene flujo de polígono (§5.2).
- [ ] Portar `extractSegmentsBetweenCutLines` (§5.3).
- [ ] Crear controlador/estado con los campos del contrato (§4) y el
      esqueleto de `addPoint`/`updatePoint`/`clearAll` (§5.4).
- [ ] Conectar al mapa: `onTap`, `onMapEvent` para zoom, y exponer
      `getVisibleGasoductoPolylines()` (§6).
- [ ] Implementar el widget de capa con polylines, drag markers y warning
      (§5.5).
- [ ] Implementar botón de modo y panel de control (§5.5).
- [ ] Reutilizar o implementar el filtro de solapamientos (§8).
- [ ] Abrir diálogo (descripción / tipo / estado) y mapear a
      `SegmentoEntity`, corrigiendo latFin/lngFin (§9).
- [ ] Llamar al servicio que persiste los segmentos (backend u offline).
- [ ] Probar con zoom < 12 (layer oculto), con líneas que se crucen
      (warning), con polylines que solo cruzan una línea (regla mitad-hacia-otra).

---

## 12. Referencias al código web

| Archivo | Líneas |
|---|---|
| `lib/views/desherbajemain/widgets/layers/lines_cut_layer.dart` | UI, drag markers, botón de modo, widget de control |
| `lib/views/desherbajemain/widgets/layers/lines_cut_layer_controller.dart` | Estado, algoritmo completo, flujo `extractAndApplyCut` |
| `lib/core/utils/polyline_polygon_intersector.dart:303-468` | Modelo `PolylineSegment` (helpers `hitValue`, longitud, copia) |
| `lib/views/desherbajemain/widgets/layers/extracted_segments_layer_controller.dart` | Capa consumidora que pinta los segmentos extraídos |
| `lib/views/desherbajemain/desherbaje_controller.dart:87` | `polylinesVisibles` (contrato con gasoductos) |

---

# Anexos — código autocontenido

Todo lo que sigue es copia directa (o adaptación trivial) del código de
producción del proyecto web. El objetivo es que el documento no dependa del
acceso al repositorio web: el equipo móvil puede implementar la
funcionalidad **solo con este fichero**.

---

## Anexo A — `PolylineHitData` y extractores de metadatos

Las polylines de gasoductos en el proyecto web llevan en su campo
`hitValue` una instancia de `PolylineHitData`. Los extractores de
`ctId`/`name`/`traza` de `PolylineSegment` leen de ahí.

### A.1 Contrato `PolylineHitData`

Copia de `lib/core/ui/map/polyline/polyline_hit_data.dart` (archivo
completo, 77 líneas — aquí los campos imprescindibles):

```dart
import 'package:flutter_map/flutter_map.dart';

class PolylineHitData {
  final String id;
  final String? ct;                       // Código del CT (p.ej. "BARCELONA")
  final String? name;                     // Nombre de la traza
  final int index;
  final Map<String, dynamic>? jsonData;
  final String? originalHitValue;

  PolylineHitData({
    required this.id,
    this.jsonData,
    this.originalHitValue,
    required this.index,
    this.ct,
    this.name,
  });

  bool get hasJsonData => jsonData?.isNotEmpty ?? false;
  dynamic operator [](String key) => jsonData?[key];

  @override
  String toString() => id;
}
```

> Si en el móvil la capa de gasoductos ya construye un `hitValue` propio
> con otra clase, basta con que exponga los campos `ct` y `name` accesibles
> por *dynamic dispatch* (`(hitValue as dynamic).ct`) — los extractores ya
> lo hacen así.

### A.2 `PolylineSegment` completo (con extractores integrados)

Reemplaza al esqueleto del §5.2 del cuerpo principal. Copia de
`lib/core/utils/polyline_polygon_intersector.dart:303-468` adaptado:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// Si tu proyecto ya tiene una referencia al usuario logueado con sus CTs,
// inyéctala aquí. En web vive en AppDI.userRepo.loggedUser.cts.
// Contrato esperado: List<({String ct, int ctid})>.
typedef LoggedUserCtsProvider = List<({String ct, int ctid})> Function();

class PolylineSegment {
  final int id;
  final String name;
  final int ctId;
  final String traza;
  final List<LatLng> points;
  final Polyline originalPolyline;
  final List<LatLng>? sourcePolygon;   // sólo lo usa el flujo de polígono; null aquí

  bool selected = false;
  String description = '';
  TipoActividad tipoActividad = TipoActividad.desherbajeSelectivo;
  EstadoActividad estado = EstadoActividad.propuesta;

  PolylineSegment({
    required this.id,
    String? name,
    int? ctId,
    String? traza,
    required this.points,
    required this.originalPolyline,
    this.sourcePolygon,
    this.selected = false,
    this.description = '',
    required LoggedUserCtsProvider ctsProvider,
  })  : ctId  = ctId  ?? _extractCtId(originalPolyline, ctsProvider),
        traza = traza ?? _extractTraza(originalPolyline),
        name  = name  ?? _extractName(originalPolyline);

  // ---- Extractores ----

  static int _extractCtId(Polyline p, LoggedUserCtsProvider ctsProvider) {
    try {
      final hit = p.hitValue;
      if (hit != null) {
        final ctName = (hit as dynamic).ct?.toString() ?? '';
        final cts = ctsProvider();
        if (cts.isEmpty) return 0;
        final match = cts.firstWhere(
          (c) => c.ct == ctName,
          orElse: () => cts.first,
        );
        return match.ctid;
      }
    } catch (e) {
      debugPrint('⚠️ PolylineSegment._extractCtId: $e');
    }
    return 0;
  }

  static String _extractTraza(Polyline p) {
    try {
      final hit = p.hitValue;
      if (hit != null) return (hit as dynamic).name?.toString() ?? '';
    } catch (_) {}
    return '';
  }

  static String _extractName(Polyline p) {
    try {
      final hit = p.hitValue;
      if (hit != null) {
        final ct = (hit as dynamic).ct?.toString() ?? '';
        final nm = (hit as dynamic).name?.toString() ?? '';
        if (ct.isNotEmpty && nm.isNotEmpty) return '$ct \n $nm';
        if (nm.isNotEmpty) return nm;
        if (ct.isNotEmpty) return ct;
      }
    } catch (_) {}
    return 'Segmento sin nombre';
  }

  // ---- Utilidades ----

  Polyline toPolyline({Color? color, double? strokeWidth}) => Polyline(
        points: points,
        color: color ?? originalPolyline.color,
        strokeWidth: strokeWidth ?? originalPolyline.strokeWidth,
        borderColor: originalPolyline.borderColor,
        borderStrokeWidth: originalPolyline.borderStrokeWidth,
      );

  double get lengthInMeters {
    if (points.length < 2) return 0;
    const d = Distance();
    double total = 0;
    for (var i = 0; i < points.length - 1; i++) {
      total += d.as(LengthUnit.Meter, points[i], points[i + 1]);
    }
    return total;
  }

  LatLng get centerPoint {
    if (points.isEmpty)   return const LatLng(0, 0);
    if (points.length == 1) return points[0];
    return points[points.length ~/ 2];
  }
}
```

**Uso**: al construir un `PolylineSegment` desde el motor (§5.3) pásale el
provider con los CTs del usuario logueado:

```dart
final ctsProvider = () => Session.currentUser?.cts ?? const [];
final seg = PolylineSegment(
  id: DateTime.now().microsecondsSinceEpoch,
  points: segPts,
  originalPolyline: polyline,
  ctsProvider: ctsProvider,
);
```

---

## Anexo B — Enums `TipoActividad` y `EstadoActividad`

Copia directa de
`lib/domain/entities/segmento_entity.dart:32-74`. Los valores `descripcion`
son los que la DB (`inventario_segmentos`) espera en serialización; las
`etiqueta` son las que se muestran al usuario.

```dart
enum TipoActividad {
  desbroceManual      ('desbroce_manual',      'Desbroce Manual'),
  desbroceMecanico    ('desbroce_mecanico',    'Desbroce Mecánico'),
  deshierbePosiciones ('deshierbe_posiciones', 'Deshierbe Posiciones'),
  desherbajeSelectivo ('deshierbe_selectivo',  'Deshierbe Selectivo'),
  desratizacion       ('desratizacion',        'Desratización'),
  resiembre           ('resiembre',            'Resiembre'),
  talaArboles         ('tala_arboles',         'Tala de Árboles');

  final String descripcion;
  final String etiqueta;
  const TipoActividad(this.descripcion, this.etiqueta);

  static TipoActividad fromString(String value) =>
      TipoActividad.values.firstWhere(
        (e) => e.descripcion == value,
        orElse: () => TipoActividad.desherbajeSelectivo,
      );
}

enum EstadoActividad {
  propuesta    ('propuesta',   'Propuesta'),
  validada     ('validada',    'Validada'),
  contratista  ('contratita',  'Contratista'),   // typo histórico: 'contratita'
  ejecucion    ('ejecución',   'En Ejecución'),
  finalizada   ('finalizada',  'Finalizada'),
  cerrada      ('cerrada',     'Cerrada');

  final String descripcion;
  final String etiqueta;
  const EstadoActividad(this.descripcion, this.etiqueta);

  static EstadoActividad fromString(String value) =>
      EstadoActividad.values.firstWhere(
        (e) => e.descripcion.toLowerCase() == value.toLowerCase(),
        orElse: () => EstadoActividad.propuesta,
      );
}
```

⚠️ Mantener el typo `'contratita'` (sin la segunda "s") si el backend móvil
comparte la misma tabla `inventario_segmentos` que el web.

---

## Anexo C — Widget `LinesCutLayer` completo (sin GetX / sin ActionManager)

Adaptación literal de `lib/views/desherbajemain/widgets/layers/lines_cut_layer.dart`
eliminando dependencias de `AutoGetBuilder`, `TypedActionManagerWidget`,
`leulit_flutter_fullresponsive` (`.w`/`.h`) y `auto_size_text_plus`.

El widget recibe el estado y un par de callbacks; el equipo móvil lo
envuelve con el notifier que use (GetX `Obx`, `ChangeNotifier`, Bloc,
Riverpod…).

### C.1 Callbacks y API

```dart
class LinesCutCallbacks {
  final VoidCallback onToggleCanCut;               // alterna dibujo
  final VoidCallback onClearAll;                   // limpia todo
  final VoidCallback onClearActive;                // limpia línea activa
  final VoidCallback onApplyCut;                   // extractAndApplyCut()
  final ValueChanged<int> onSetActiveLine;         // 1 ó 2
  final void Function(int line, int idx, LatLng pos) onDragPoint;

  const LinesCutCallbacks({
    required this.onToggleCanCut,
    required this.onClearAll,
    required this.onClearActive,
    required this.onApplyCut,
    required this.onSetActiveLine,
    required this.onDragPoint,
  });
}
```

### C.2 Layer principal

```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
// Paquete de drag markers: flutter_map_dragmarker (pub.dev) o equivalente.
// API esperada: DragMarkers(markers: [...], onMarkerDragEnd: (marker, pos) {})
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';

class LinesCutLayer extends StatelessWidget {
  const LinesCutLayer({
    super.key,
    required this.state,
    required this.callbacks,
  });

  final LinesCutState state;                       // §5.4
  final LinesCutCallbacks callbacks;

  static const _line1Color = Colors.green;
  static const _line2Color = Colors.purple;

  @override
  Widget build(BuildContext context) {
    if (!state.cutStateOn || !state.zoomOk) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;

    final dragMarkers = <Marker>[
      for (var i = 0; i < state.line1Points.length; i++)
        _buildDragMarker(
          point: state.line1Points[i],
          color: _line1Color,
          lineNumber: 1,
          pointIndex: i,
          isActive: state.activeLine == 1,
        ),
      for (var i = 0; i < state.line2Points.length; i++)
        _buildDragMarker(
          point: state.line2Points[i],
          color: _line2Color,
          lineNumber: 2,
          pointIndex: i,
          isActive: state.activeLine == 2,
        ),
    ];

    return Stack(
      children: [
        // Botón de modo (arriba-derecha)
        Positioned(
          right: size.width * 0.01,
          top:   size.height * 0.01,
          child: _ModeButton(
            icon:  state.canCut ? Icons.close : Icons.content_cut,
            label: state.canCut ? 'Finalizar corte' : 'Líneas de corte',
            colors: state.canCut
                ? [Colors.purple.shade400, Colors.purple.shade700]
                : [Colors.green.shade400,  Colors.green.shade700],
            onTap: () {
              if (state.canCut) callbacks.onClearAll();
              callbacks.onToggleCanCut();
            },
          ),
        ),

        // Panel de control (arriba-izquierda) visible sólo en modo dibujo
        if (state.canCut)
          Positioned(
            left: size.width * 0.01,
            top:  size.height * 0.01,
            width:  size.width  * 0.2,
            height: size.height * 0.17,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              child: LinesCutControlWidget(
                state: state,
                callbacks: callbacks,
              ),
            ),
          ),

        // Línea 1
        if (state.line1Points.length == 2)
          PolylineLayer(polylines: [
            Polyline(
              points: state.line1Points,
              color:  _line1Color,
              strokeWidth: state.activeLine == 1 ? 4.0 : 3.0,
              borderColor: Colors.white,
              borderStrokeWidth: 1.0,
            ),
          ]),

        // Línea 2
        if (state.line2Points.length == 2)
          PolylineLayer(polylines: [
            Polyline(
              points: state.line2Points,
              color:  _line2Color,
              strokeWidth: state.activeLine == 2 ? 4.0 : 3.0,
              borderColor: Colors.white,
              borderStrokeWidth: 1.0,
            ),
          ]),

        // Marcadores arrastrables
        if (dragMarkers.isNotEmpty)
          DragMarkers(
            markers: dragMarkers,
            onMarkerDragEnd: (marker, newPos) {
              final key = (marker.key as ValueKey<String>).value;
              final parts = key.split('_');
              final line = int.parse(parts[0].replaceAll('line', ''));
              final idx  = int.parse(parts[1].replaceAll('point', ''));
              callbacks.onDragPoint(line, idx, newPos);
            },
          ),

        // Warning de intersección
        if (state.hasIntersectionError) _buildIntersectionWarning(state),
      ],
    );
  }

  static Marker _buildDragMarker({
    required LatLng point,
    required Color  color,
    required int    lineNumber,
    required int    pointIndex,
    required bool   isActive,
  }) {
    return Marker(
      key: ValueKey('line${lineNumber}_point$pointIndex'),
      point: point,
      width: 24,
      height: 24,
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive ? Colors.white : Colors.grey.shade300,
            width: isActive ? 3 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '${pointIndex + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildIntersectionWarning(LinesCutState s) {
    if (s.line1Points.length != 2 || s.line2Points.length != 2) {
      return const SizedBox.shrink();
    }
    final lat = (s.line1Points[0].latitude  + s.line1Points[1].latitude  +
                 s.line2Points[0].latitude  + s.line2Points[1].latitude) / 4;
    final lng = (s.line1Points[0].longitude + s.line1Points[1].longitude +
                 s.line2Points[0].longitude + s.line2Points[1].longitude) / 4;

    return MarkerLayer(markers: [
      Marker(
        point: LatLng(lat, lng),
        width: 60,
        height: 60,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.9),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: const Icon(Icons.warning_rounded, color: Colors.white, size: 32),
        ),
      ),
    ]);
  }
}
```

### C.3 Botón de modo

```dart
class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  final IconData     icon;
  final String       label;
  final List<Color>  colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end:   Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

### C.4 Panel de control (selector de línea + botones Aplicar/Limpiar)

```dart
class LinesCutControlWidget extends StatelessWidget {
  const LinesCutControlWidget({
    super.key,
    required this.state,
    required this.callbacks,
  });

  final LinesCutState state;
  final LinesCutCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    final hasError = state.hasIntersectionError;

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasError ? Colors.red : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _lineButton(
                  lineNumber: 1,
                  color: Colors.green,
                  isActive: state.activeLine == 1,
                  pointCount: state.line1Points.length,
                  onTap: () => callbacks.onSetActiveLine(1),
                )),
                const SizedBox(width: 12),
                Expanded(child: _lineButton(
                  lineNumber: 2,
                  color: Colors.purple,
                  isActive: state.activeLine == 2,
                  pointCount: state.line2Points.length,
                  onTap: () => callbacks.onSetActiveLine(2),
                )),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (state.areLinesCutReady) ...[
                  _actionButton(
                    icon: Icons.content_cut,
                    label: 'Aplicar Corte',
                    color: Colors.blue,
                    onTap: callbacks.onApplyCut,
                  ),
                  const SizedBox(width: 8),
                ],
                _actionButton(
                  icon: Icons.clear,
                  label: 'Limpiar',
                  color: Colors.orange,
                  onTap: callbacks.onClearActive,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineButton({
    required int lineNumber,
    required Color color,
    required bool isActive,
    required int pointCount,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.15) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? color : Colors.grey.shade300,
            width: isActive ? 3 : 1,
          ),
          boxShadow: isActive ? [
            BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, spreadRadius: 1),
          ] : null,
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width:  isActive ? 16 : 12,
                  height: isActive ? 16 : 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isActive
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Línea $lineNumber',
                  style: TextStyle(
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    fontSize:  isActive ? 14 : 13,
                    color:     isActive ? color : Colors.grey.shade700,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.check_circle, size: 16, color: color),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$pointCount/2 puntos',
              style: TextStyle(
                fontSize: 11,
                color: isActive ? color : Colors.grey.shade600,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

> Si el móvil usa GetX el wrapper es: `Obx(() => LinesCutLayer(state: state, callbacks: cb))`.
> Con `ChangeNotifier`: `AnimatedBuilder(animation: notifier, builder: (_, __) => LinesCutLayer(...))`.

### C.5 Dependencia de paquete drag markers

En `pubspec.yaml` del móvil:

```yaml
dependencies:
  flutter_map_dragmarker: ^7.0.0   # o la versión compatible con tu flutter_map
```

La API `DragMarkers(markers, onMarkerDragEnd)` que usa el widget de §C.2
es la misma que expone ese paquete, así que no hacen falta adaptaciones.

---

## Anexo D — Diálogo de captura (contrato de retorno)

El flujo `extractAndApplyCut()` de la web llama a
`DesherbajeDialogs.segmentoDialog(...)` (firma real:
`Future<SegmentoEntity?> segmentoDialog(SegmentoEntity segmento)`), y
consume del retorno sólo tres campos: `descripcion`, `tipoActividad`,
`estado`.

### D.1 Contrato mínimo portable

Para no obligar al móvil a portar el diálogo completo del web (350+
líneas), se recomienda este contrato simple:

```dart
class CutDialogResult {
  final String           descripcion;
  final TipoActividad    tipoActividad;
  final EstadoActividad  estado;
  final bool             validadoEnagas;     // opcional, default false

  const CutDialogResult({
    required this.descripcion,
    required this.tipoActividad,
    required this.estado,
    this.validadoEnagas = false,
  });
}

/// Abre un diálogo modal y devuelve null si el usuario cancela.
///
/// Parámetros de conveniencia para mostrar en cabecera (sólo lectura):
///   [ctName]    → nombre del CT (p.ej. "BARCELONA")
///   [trazaName] → nombre de la traza
///   [lengthMeters] → longitud total de los segmentos extraídos
typedef CutDialogOpener = Future<CutDialogResult?> Function({
  required String ctName,
  required String trazaName,
  required double lengthMeters,
  String          initialDescripcion,
  TipoActividad   initialTipoActividad,
  EstadoActividad initialEstado,
});
```

### D.2 Uso desde el controlador

```dart
Future<void> extractAndApplyCut({
  required CutDialogOpener openDialog,
  required List<Polyline>  visiblePolylines,
  required Future<List<PolylineSegment>> Function(List<PolylineSegment>) removeOverlapping,
  required void Function(List<PolylineSegment>) onExtracted,
  required LoggedUserCtsProvider ctsProvider,
}) async {
  if (!state.areLinesCutReady) {
    // Avisar al usuario y salir.
    return;
  }

  final raw = extractSegmentsBetweenCutLines(
    line1Points: state.line1Points,
    line2Points: state.line2Points,
    visiblePolylines: visiblePolylines,
  );
  final filtered = await removeOverlapping(raw);
  if (filtered.isEmpty) {
    // "Sin resultados": los segmentos ya existen o no cruzan → mostrar aviso.
    return;
  }

  // Cabecera informativa del diálogo (basta con la primera referencia).
  final firstCt = filtered.first;
  final totalMeters = filtered.fold<double>(0, (s, seg) => s + seg.lengthInMeters);

  final result = await openDialog(
    ctName:        'CT ${firstCt.ctId}',
    trazaName:     firstCt.traza,
    lengthMeters:  totalMeters,
    initialDescripcion:   '',
    initialTipoActividad: TipoActividad.desherbajeSelectivo,
    initialEstado:        EstadoActividad.propuesta,
  );

  // Usuario canceló → conservar líneas para que pueda reintentar.
  if (result == null) return;

  for (final seg in filtered) {
    seg.description   = result.descripcion;
    seg.tipoActividad = result.tipoActividad;
    seg.estado        = result.estado;
  }

  onExtracted(filtered);
  clearAll(state);
}
```

### D.3 Mapeo final a `SegmentoEntity`

Cuando `onExtracted` persiste en backend / DB local:

```dart
final entity = SegmentoEntity.empty()
  ..ubicacionGis   = seg.points
  ..latInicio      = seg.points.first.latitude
  ..lngInicio      = seg.points.first.longitude
  ..latFin         = seg.points.last.latitude   // corregido vs. web
  ..lngFin         = seg.points.last.longitude  // corregido vs. web
  ..ctId           = seg.ctId
  ..traza          = seg.traza
  ..descripcion    = seg.description
  ..tipoActividad  = seg.tipoActividad
  ..estado         = seg.estado
  ..validadoEnagas = false;
```

(Recordad el bug §9 del cuerpo: en web los campos `latFin`/`lngFin` se
asignan a `points.first` por error — al portar, usar `points.last`.)

---

Con los anexos A, B, C y D el documento queda autocontenido: matemática,
motor, estado, widget completo, enums de dominio, contrato del `hitValue`
y contrato del diálogo. No requiere acceso al repositorio web.

