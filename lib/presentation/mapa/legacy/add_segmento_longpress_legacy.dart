// ignore_for_file: unused_element

/// Código archivado — NO IMPORTAR en producción.
///
/// Flujo original de alta de segmento por long-press sobre el mapa:
///   · `isAddingSegmento`: modo activo mientras el usuario captura puntos.
///   · `nuevosPuntos`: vértices capturados vía long-press.
///   · `addSegmento` / `cancelarSegmento` / `crearSegmento` / `onMapLongPress`
///     implementan el ciclo completo.
///
/// Se descartó en favor del flujo de "Líneas de corte" (ver
/// `presentation/mapa/lines_cut/`). Se conserva aquí por si se decide volver
/// a habilitarlo — en ese caso:
///
///   1. Aplicar el mixin [LegacyAddSegmentoLongpressMixin] al
///      `MapaGlobalController`.
///   2. Re-añadir en `mapa_global_page.dart`:
///        · `onLongPress: (_, p) => controller.onMapLongPress(p)` en
///          `MapOptions`.
///        · Las capas visuales de `nuevosPuntos` (polyline roja + markers).
///        · El botón "+" + par cancelar/confirmar (estaban en `_AddSegmentoButton`
///          y `_AddSegmentoActiveActions`).
///
/// Requisitos del mixin: rutas `AppRoutes.detalle` y entidad
/// `SegmentoEntity.empty()` con los getters usados.
library;

import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/app_router.dart';
import '../../../domain/entities/segmento_entity.dart';

mixin LegacyAddSegmentoLongpressMixin on GetxController {
  /// Umbral original del zoom mínimo para habilitar el alta por long-press.
  static const double addSegmentoMinZoom = 14.0;

  final isAddingSegmento = false.obs;
  final nuevosPuntos = <LatLng>[].obs;

  /// Reimplementar por el controller concreto: zoom actual del mapa.
  double get currentZoomValue;

  bool get canAddSegmento => currentZoomValue > addSegmentoMinZoom;

  void addSegmento() {
    if (!canAddSegmento) return;
    nuevosPuntos.clear();
    isAddingSegmento.value = true;
  }

  void cancelarSegmento() {
    isAddingSegmento.value = false;
    nuevosPuntos.clear();
  }

  /// Al confirmar, construye un [SegmentoEntity] con la traza capturada y
  /// navega al detalle para editarlo.
  void crearSegmento() {
    if (nuevosPuntos.length < 2) return;
    final puntos = List<LatLng>.from(nuevosPuntos);
    final nuevo = SegmentoEntity.empty()
      ..ubicacionGis = puntos
      ..latInicio = puntos.first.latitude
      ..lngInicio = puntos.first.longitude
      ..latFin = puntos.last.latitude
      ..lngFin = puntos.last.longitude;

    isAddingSegmento.value = false;
    nuevosPuntos.clear();

    Get.toNamed(AppRoutes.detalle, arguments: nuevo);
  }

  /// Invocar desde `MapOptions.onLongPress`.
  void onMapLongPress(LatLng point) {
    if (!isAddingSegmento.value) return;
    if (!canAddSegmento) return;
    nuevosPuntos.add(point);
  }
}
