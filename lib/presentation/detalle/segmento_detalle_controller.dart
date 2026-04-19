import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../../core/my_getx_controller.dart';
import '../../core/services/gasoductos_service.dart';
import '../../data/repository/auth_repository_impl.dart';
import '../../data/repository/segmento_repository_impl.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/entities/user_entity.dart';

class SegmentoDetalleController extends MyGetxController {
  final _authRepo = AuthRepositoryImpl();
  final _segmentoRepo = SegmentoRepositoryImpl();

  late final SegmentoEntity segmento;
  final user = Rx<UserModel?>(null);

  /// Controlador del mapa, expuesto para que los botones +/- de zoom puedan
  /// invocar `mapController.move`.
  final mapController = MapController();

  final estado = Rx<EstadoActividad>(EstadoActividad.propuesta);
  final tipoActividad = Rx<TipoActividad>(TipoActividad.desherbajeSelectivo);
  final descripcion = ''.obs;
  final isSaving = false.obs;

  /// Centro inicial del mapa: centro del segmento o, si no tiene, centroide
  /// de Madrid como fallback razonable.
  late final LatLng initialCenter;
  late final double initialZoom;

  /// Polyline destacada (el segmento actual sobre el mapa).
  late final Polyline highlightedSegment;

  /// Polylines de gasoductos cacheadas en el `GasoductosService`.
  final gasoductosPolylines = <Polyline>[].obs;

  GasoductosService get _gasoductosService =>
      Get.find<GasoductosService>();

  @override
  void myOnInit() {
    final args = Get.arguments;
    segmento = args is SegmentoEntity ? args : SegmentoEntity.empty();
    estado.value = segmento.estado;
    tipoActividad.value = segmento.tipoActividad;
    descripcion.value = segmento.descripcion;

    _initMap();
    _loadUser();
    _ensureGasoductos();
  }

  Future<void> _loadUser() async {
    user.value = await _authRepo.getCurrentUser();
  }

  /// Nombre legible del CT al que pertenece el segmento. Reactivo respecto a
  /// [user]: en cuanto se carga el usuario, los `Obx` que usen este getter se
  /// reconstruyen automáticamente.
  String get ctName {
    final name = user.value?.ctNameById(segmento.ctId);
    if (name != null && name.isNotEmpty) return name;
    return 'CT ${segmento.ctId}';
  }

  void _initMap() {
    final pts = segmento.ubicacionGis;
    if (pts.isNotEmpty) {
      initialCenter = pts[pts.length ~/ 2];
      initialZoom = 16;
    } else if (segmento.latInicio != null && segmento.lngInicio != null) {
      initialCenter = LatLng(segmento.latInicio!, segmento.lngInicio!);
      initialZoom = 15;
    } else {
      initialCenter = const LatLng(40.4168, -3.7038);
      initialZoom = 7;
    }

    highlightedSegment = Polyline(
      points: pts.isEmpty ? const [] : pts,
      color: const Color(0xFFFFC107),
      strokeWidth: 6,
      borderColor: Colors.white,
      borderStrokeWidth: 2,
    );
  }

  Future<void> _ensureGasoductos() async {
    await _gasoductosService.ensureLoaded();
    gasoductosPolylines.assignAll(_gasoductosService.polylines);
    ever<List<Polyline>>(
      _gasoductosService.polylines,
      gasoductosPolylines.assignAll,
    );
  }

  void zoomIn() {
    final cam = mapController.camera;
    mapController.move(cam.center, (cam.zoom + 1).clamp(5, 20));
  }

  void zoomOut() {
    final cam = mapController.camera;
    mapController.move(cam.center, (cam.zoom - 1).clamp(5, 20));
  }

  /// Actualiza el segmento en backend (estado/tipo/descripción) usando el
  /// repositorio offline-first.
  Future<void> guardar() async {
    isSaving.value = true;
    try {
      segmento.estado = estado.value;
      segmento.tipoActividad = tipoActividad.value;
      segmento.descripcion = descripcion.value;
      if (segmento.id != null) {
        await _segmentoRepo.updateEstado(segmento.id!, estado.value);
      }
      Get.back(result: segmento);
    } finally {
      isSaving.value = false;
    }
  }
}
