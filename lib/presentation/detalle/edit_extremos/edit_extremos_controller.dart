import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/app_di.dart';
import '../../../core/widgets/endpoint_pin.dart';
import '../../../core/services/gasoductos_service.dart';
import '../../../data/repository/segmento_repository_impl.dart';
import '../../../domain/entities/segmento_entity.dart';
import 'edit_extremos_math.dart';

/// Qué extremo del segmento se está arrastrando.
enum EndpointKind { inicio, fin }

/// Controller del diálogo de edición de extremos.
///
/// Mantiene el estado reactivo mientras el usuario arrastra los markers A/B
/// sobre el mapa: valida el snap al gasoducto más cercano, recalcula la
/// polilínea recortada en vivo y persiste el cambio al cerrar.
///
/// No está registrado globalmente: el `EditExtremosDialog` lo instancia con
/// `Get.put(tag: ...)` en su `initState` y lo elimina en `dispose`.
class EditExtremosController extends GetxController {
  EditExtremosController({
    required this.original,
    SegmentoRepositoryImpl? segmentoRepo,
    GasoductosService? gasoductos,
    this._snapMaxMeters = 25,
  })  : _repo = segmentoRepo ?? SegmentoRepositoryImpl(),
        _gasoductos = gasoductos ?? AppDI.gasoductosService;

  final SegmentoEntity original;
  final SegmentoRepositoryImpl _repo;
  final GasoductosService _gasoductos;
  final double _snapMaxMeters;

  // ─────────────────────────────── Estado reactivo ───────────────────────────

  /// Posición snapeada del extremo de inicio.
  late final Rx<LatLng> inicio;

  /// Posición snapeada del extremo de fin.
  late final Rx<LatLng> fin;

  /// Polilínea del segmento recortada según los extremos actuales.
  final ubicacionGisDraft = <LatLng>[].obs;

  /// Mensaje transitorio mostrado cuando un drop cae fuera del gasoducto.
  /// El widget marker lo escucha para revertir visualmente su posición.
  final snapError = ''.obs;

  /// Flag para bloquear el botón "Guardar" durante la persistencia.
  final isSaving = false.obs;

  /// Versión incremental usada como trigger para que los markers arrastrables
  /// se resincronicen con el estado del controller cuando hay un rechazo.
  final revertTick = 0.obs;

  /// Verdadero mientras el usuario está arrastrando un marker. El diálogo
  /// lo usa para desactivar `InteractiveFlag.drag` del mapa y así evitar
  /// que el gesto de pan del mapa gane al del marker.
  final isDraggingMarker = false.obs;

  // ─────────────────────────────── Snap estado interno ───────────────────────

  // Guarda a qué polilínea de gasoducto está pegado cada extremo para poder
  // recortar correctamente la ubicacionGis.
  Polyline? _inicioGasoducto;
  int _inicioSegIdx = 0;
  double _inicioT = 0;

  Polyline? _finGasoducto;
  int _finSegIdx = 0;
  double _finT = 0;

  // ─────────────────────────────── Ciclo de vida ─────────────────────────────

  @override
  void onInit() {
    super.onInit();
    final origInicio = (original.latInicio != null && original.lngInicio != null)
        ? LatLng(original.latInicio!, original.lngInicio!)
        : (original.ubicacionGis.isNotEmpty
            ? original.ubicacionGis.first
            : const LatLng(0, 0));
    final origFin = (original.latFin != null && original.lngFin != null)
        ? LatLng(original.latFin!, original.lngFin!)
        : (original.ubicacionGis.isNotEmpty
            ? original.ubicacionGis.last
            : const LatLng(0, 0));

    inicio = origInicio.obs;
    fin = origFin.obs;
    ubicacionGisDraft.assignAll(original.ubicacionGis);

    // Intenta snapear los extremos originales para que ya queden pegados al
    // gasoducto al abrir el diálogo — facilita truncar al guardar sin drag.
    _trySnapInitial(EndpointKind.inicio, origInicio);
    _trySnapInitial(EndpointKind.fin, origFin);
  }

  void _trySnapInitial(EndpointKind kind, LatLng raw) {
    final hit = snapToNearestGasoducto(
      raw,
      _gasoductos.polylines,
      maxMeters: _snapMaxMeters * 2, // umbral más laxo para la inicialización
    );
    if (hit == null) return;
    _applyHit(kind, hit);
  }

  // ─────────────────────────────── Interacción usuario ───────────────────────

  /// Invocado por el marker arrastrable al soltar. Si el punto queda fuera
  /// del umbral, [snapError] se rellena y el widget debe revertir el drag.
  void onDragEnd(EndpointKind kind, LatLng raw) {
    final hit = snapToNearestGasoducto(
      raw,
      _gasoductos.polylines,
      maxMeters: _snapMaxMeters,
    );
    if (hit == null) {
      snapError.value = 'Fuera del gasoducto (>${_snapMaxMeters.toInt()} m)';
      // Incrementa el tick para forzar al marker a reconciliarse con el
      // estado actual (vuelve a su posición snapeada previa).
      revertTick.value = revertTick.value + 1;
      return;
    }
    snapError.value = '';
    _applyHit(kind, hit);
  }

  void _applyHit(EndpointKind kind, NearestGasoductoHit hit) {
    if (kind == EndpointKind.inicio) {
      inicio.value = hit.projection.point;
      _inicioGasoducto = hit.polyline;
      _inicioSegIdx = hit.projection.segmentIndex;
      _inicioT = hit.projection.tAlongSegment;
    } else {
      fin.value = hit.projection.point;
      _finGasoducto = hit.polyline;
      _finSegIdx = hit.projection.segmentIndex;
      _finT = hit.projection.tAlongSegment;
    }
    _recomputeDraft();
  }

  void _recomputeDraft() {
    // Caso feliz: ambos extremos pegados al MISMO gasoducto → trunca la
    // polilínea entre ambos respetando los vértices intermedios.
    if (_inicioGasoducto != null &&
        _finGasoducto != null &&
        identical(_inicioGasoducto, _finGasoducto)) {
      final truncated = truncatePolylineAt(
        _inicioGasoducto!.points,
        inicio.value,
        fin.value,
        startSegIdx: _inicioSegIdx,
        endSegIdx: _finSegIdx,
        startT: _inicioT,
        endT: _finT,
      );
      ubicacionGisDraft.assignAll(truncated);
      return;
    }
    // Fallback: extremos en gasoductos distintos o sin snap — línea recta.
    ubicacionGisDraft.assignAll([inicio.value, fin.value]);
  }

  // ─────────────────────────────── Guardar / cancelar ────────────────────────

  bool get hasChanges =>
      inicio.value != _origInicioLatLng() ||
      fin.value != _origFinLatLng();

  LatLng _origInicioLatLng() => LatLng(
        original.latInicio ?? 0,
        original.lngInicio ?? 0,
      );
  LatLng _origFinLatLng() => LatLng(
        original.latFin ?? 0,
        original.lngFin ?? 0,
      );

  void cancelar() => Get.back<SegmentoEntity?>(result: null);

  /// Persiste el segmento actualizado en local (needs_sync=1) y devuelve la
  /// entidad actualizada al caller para que refresque su UI.
  Future<void> guardar() async {
    if (isSaving.value) return;
    if (!hasChanges) {
      Get.back<SegmentoEntity?>(result: null);
      return;
    }
    isSaving.value = true;
    try {
      final updated = original.copyWith(
        latInicio: inicio.value.latitude,
        lngInicio: inicio.value.longitude,
        latFin: fin.value.latitude,
        lngFin: fin.value.longitude,
        ubicacionGis: List<LatLng>.from(ubicacionGisDraft),
      );
      await _repo.saveLocal(updated);
      Get.back<SegmentoEntity?>(result: updated);
    } catch (e) {
      Get.snackbar(
        'Error',
        'No se han podido guardar los extremos: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
      );
    } finally {
      isSaving.value = false;
    }
  }

  // ─────────────────────────────── Exposed para UI ───────────────────────────

  /// Color semántico del marker de inicio (verde) y fin (rojo).
  Color colorFor(EndpointKind kind) =>
      kind == EndpointKind.inicio ? kColorInicio : kColorFin;

  /// Centro y zoom inicial sugeridos (fallback cuando no hay traza).
  ({LatLng center, double zoom}) get initialCamera {
    final pts = original.ubicacionGis;
    if (pts.isNotEmpty) {
      return (center: pts[pts.length ~/ 2], zoom: 17);
    }
    if (original.latInicio != null && original.lngInicio != null) {
      return (
        center: LatLng(original.latInicio!, original.lngInicio!),
        zoom: 17
      );
    }
    return (center: const LatLng(40.4168, -3.7038), zoom: 7);
  }

  /// Encuadre inicial que asegura ver el segmento completo. Devuelve `null`
  /// si no hay suficientes puntos para calcular bounds (se usa `initialCamera`
  /// como fallback en ese caso).
  CameraFit? get initialCameraFit {
    final pts = original.ubicacionGis;
    if (pts.length < 2) return null;
    return CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(pts),
      padding: const EdgeInsets.all(60),
      maxZoom: 19,
    );
  }
}
