import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:leulit_flutter_actionmanager/leulit_flutter_actionmanager.dart';

import '../../../domain/entities/segmento_entity.dart';
import 'lines_cut_engine.dart';
import 'lines_cut_math.dart';
import 'polyline_segment.dart';

typedef VisiblePolylinesProvider = List<Polyline> Function();

class LinesCutTypedActions {
  static const String prefijo = 'lines_cut_';
  static const TypedAction startCutAction = TypedAction('${prefijo}start_cut');
  static const TypedAction endCutAction = TypedAction('${prefijo}end_cut');
}

/// Zoom mínimo requerido para que la feature se renderice y acepte taps.
const double kLinesCutMinZoom = 14.0;

class LinesCutController extends GetxController {
  LinesCutController({
    required this.visiblePolylinesProvider,
    required this.ctsProvider,
  });

  /// Fuente de polylines candidatas al corte. La proporciona el padre
  /// (MapaGlobalController) a partir del viewport actual.
  final VisiblePolylinesProvider visiblePolylinesProvider;

  /// Proveedor de los CTs del usuario logueado para resolver `ctId` desde
  /// el `hitValue` textual.
  final LoggedUserCtsProvider ctsProvider;

  // ─────────────────────────── Estado reactivo ───────────────────────────

  /// Feature disponible (se activa/desactiva desde el botón de modo).
  final cutStateOn = false.obs;

  /// `map.camera.zoom > kLinesCutMinZoom`. Si false, la capa se oculta.
  final zoomOk = false.obs;

  /// El usuario está realmente dibujando (modo captura de taps activo).
  final canCut = false.obs;

  /// Qué línea recibe el próximo tap: 1 o 2.
  final activeLine = 1.obs;

  final line1Points = <LatLng>[].obs;
  final line2Points = <LatLng>[].obs;

  /// L1 y L2 completas y se cruzan entre sí → estado inválido.
  final hasIntersectionError = false.obs;

  /// Cada línea completa debe cruzar al menos una polyline de gasoducto
  /// visible. Se recalculan en `_revalidate()`; `false` mientras la línea
  /// tenga menos de 2 puntos.
  final line1CrossesTraza = false.obs;
  final line2CrossesTraza = false.obs;

  /// Lista de segmentos resultantes tras aplicar el corte. La capa que los
  /// persista los consume desde aquí y los limpia al terminar.
  final extractedSegments = <PolylineSegment>[].obs;

  // ─────────────────────────── Derivados ───────────────────────────

  bool get areLinesCutReady =>
      line1Points.length == 2 &&
      line2Points.length == 2 &&
      line1CrossesTraza.value &&
      line2CrossesTraza.value &&
      !hasIntersectionError.value;

  /// Cualquier condición que invalida el estado actual (pinta el panel en rojo).
  bool get hasValidationError =>
      hasIntersectionError.value ||
      (line1Points.length == 2 && !line1CrossesTraza.value) ||
      (line2Points.length == 2 && !line2CrossesTraza.value);

  String get statusMessage {
    if (line1Points.isEmpty) return 'Marca el primer punto de la Línea 1';
    if (line1Points.length == 1) return 'Marca el segundo punto de la Línea 1';
    if (!line1CrossesTraza.value) {
      return '⚠ La Línea 1 no cruza ningún gasoducto';
    }
    if (line2Points.isEmpty) return 'Marca el primer punto de la Línea 2';
    if (line2Points.length == 1) return 'Marca el segundo punto de la Línea 2';
    if (!line2CrossesTraza.value) {
      return '⚠ La Línea 2 no cruza ningún gasoducto';
    }
    if (hasIntersectionError.value) return '⚠ Las líneas se intersectan';
    return '✓ Líneas listas para cortar';
  }

  // ─────────────────────────── Transiciones ───────────────────────────

  /// Alterna visibilidad de la feature (botón principal "Líneas de corte").
  void toggleFeature() {
    cutStateOn.value = !cutStateOn.value;
    if (!cutStateOn.value) {
      canCut.value = false;
      clearAll();
    }
  }

  /// Alterna el modo de dibujo dentro de la feature.
  void toggleCanCut() {
    if (!cutStateOn.value) return;
    canCut.value = !canCut.value;
    if (!canCut.value) clearAll();
  }

  void setActiveLine(int n) {
    if (n != 1 && n != 2) return;
    activeLine.value = n;
  }

  /// Añade un punto a la línea activa. Al completar L1 bascula a L2.
  void addPoint(LatLng p) {
    if (!canCut.value) return;
    if (!zoomOk.value) return;
    if (activeLine.value == 1 && line1Points.length < 2) {
      line1Points.add(p);
      if (line1Points.length == 2) activeLine.value = 2;
    } else if (activeLine.value == 2 && line2Points.length < 2) {
      line2Points.add(p);
    }
    _revalidate();
  }

  /// Actualiza un punto existente (arrastre del marcador) y revalida.
  void updatePoint(int line, int index, LatLng p) {
    if (line == 1 && index < line1Points.length) {
      line1Points[index] = p;
    } else if (line == 2 && index < line2Points.length) {
      line2Points[index] = p;
    }
    _revalidate();
  }

  /// Borra solo la línea activa.
  void clearActive() {
    if (activeLine.value == 1) {
      line1Points.clear();
    } else {
      line2Points.clear();
    }
    _revalidate();
  }

  /// Borra ambas líneas.
  void clearAll() {
    line1Points.clear();
    line2Points.clear();
    activeLine.value = 1;
    hasIntersectionError.value = false;
    line1CrossesTraza.value = false;
    line2CrossesTraza.value = false;
  }

  void updateZoom(double zoom) {
    zoomOk.value = zoom > kLinesCutMinZoom;
  }

  void _revalidate() {
    final visibles = visiblePolylinesProvider();
    line1CrossesTraza.value = line1Points.length == 2 &&
        segmentCrossesAnyPolyline(line1Points[0], line1Points[1], visibles);
    line2CrossesTraza.value = line2Points.length == 2 &&
        segmentCrossesAnyPolyline(line2Points[0], line2Points[1], visibles);

    if (line1Points.length == 2 && line2Points.length == 2) {
      hasIntersectionError.value = doSegmentsIntersect(
        line1Points[0],
        line1Points[1],
        line2Points[0],
        line2Points[1],
      );
    } else {
      hasIntersectionError.value = false;
    }
  }

  /// Ejecuta el motor de extracción sobre las polylines visibles. No persiste
  /// nada: deja el resultado en [extractedSegments] para que el consumidor
  /// (capa de segmentos extraídos / flujo de diálogo) lo procese.
  ///
  /// Si no hay resultados, deja la lista vacía y no modifica las líneas.
  List<PolylineSegment> applyCut() {
    if (!areLinesCutReady) return const [];
    final raw = extractSegmentsBetweenCutLines(
      line1Points: line1Points.toList(),
      line2Points: line2Points.toList(),
      visiblePolylines: visiblePolylinesProvider(),
      ctsProvider: ctsProvider,
    );
    extractedSegments.assignAll(raw);
    return raw;
  }

  /// Aplica los valores capturados en el diálogo a todos los segmentos
  /// extraídos. Se llama tras un diálogo confirmado.
  void applyDialogToExtracted({
    required String descripcion,
    required TipoActividad tipoActividad,
    required EstadoActividad estado,
  }) {
    for (final s in extractedSegments) {
      s.description = descripcion;
      s.tipoActividad = tipoActividad;
      s.estado = estado;
    }
  }

  /// Borra el resultado del último corte (no toca las líneas de corte).
  void clearExtracted() => extractedSegments.clear();
}
