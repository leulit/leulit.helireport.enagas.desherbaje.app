import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../core/services/gasoductos_service.dart';
import '../../data/repository/actividad_repository_impl.dart';
import '../../domain/entities/actividad_entity.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/usecases/get_actividades_usecase.dart';

class SegmentoMapInfo {
  final SegmentoEntity segmento;
  final ActividadEntity actividad;
  final List<LatLng> points;
  final Color color;
  final LatLng centroid;

  const SegmentoMapInfo({
    required this.segmento,
    required this.actividad,
    required this.points,
    required this.color,
    required this.centroid,
  });
}

class MapaGlobalController extends GetxController {
  final mapController = MapController();

  final gasoductosPolylines = <Polyline>[].obs;
  final actividadesSegmentos = <SegmentoMapInfo>[].obs;
  final isLoadingGasoductos = false.obs;
  final isLoadingActividades = false.obs;
  final errorGasoductos = Rx<String?>(null);
  final errorActividades = Rx<String?>(null);
  final currentZoom = 0.0.obs;

  void onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd || event is MapEventScrollWheelZoom) {
      currentZoom.value = mapController.camera.zoom;
    }
  }

  late final GetSegmentosUseCase _actividadesUseCase;
  GasoductosService get _gasoductosService => Get.find<GasoductosService>();

  bool get isLoading =>
      isLoadingGasoductos.value || isLoadingActividades.value;

  @override
  void onInit() {
    super.onInit();
    _actividadesUseCase = GetSegmentosUseCase(ActividadRepositoryImpl());
    // Sincronizar polylines del servicio con el observable local
    ever(_gasoductosService.polylines, (lines) => gasoductosPolylines.assignAll(lines));
    loadAll();
  }

  Future<void> loadAll() async {
    await Future.wait([loadGasoductos(), loadActividades()]);
    _fitAllBounds();
  }

  Future<void> reloadAll() async {
    await Future.wait([
      loadGasoductos(forceRefresh: true),
      loadActividades(),
    ]);
    _fitAllBounds();
  }

  Future<void> reloadActividades() async {
    await loadActividades();
    _fitAllBounds();
  }

  Future<void> loadGasoductos({bool forceRefresh = false}) async {
    isLoadingGasoductos.value = true;
    errorGasoductos.value = null;
    try {
      if (forceRefresh) {
        await _gasoductosService.reload();
      } else {
        await _gasoductosService.ensureLoaded();
      }
      gasoductosPolylines.assignAll(_gasoductosService.polylines);
    } catch (e) {
      errorGasoductos.value = 'Error cargando gasoductos';
      debugPrint('MapaGlobal gasoductos: $e');
    } finally {
      isLoadingGasoductos.value = false;
    }
  }

  Future<void> loadActividades() async {
    isLoadingActividades.value = true;
    errorActividades.value = null;
    try {
      final result = await _actividadesUseCase.execute();
      if (result.isFailure) {
        errorActividades.value = 'Error cargando actividades';
        return;
      }
      final actividades = result.dataOrNull ?? [];
      final segmentos = <SegmentoMapInfo>[];
      for (final actividad in actividades) {
        for (final segmento in actividad.segmentos) {
          if (segmento.ubicacionGis.isEmpty) continue;
          final color = AppColors.accentForEstado(actividad.estado);
          segmentos.add(SegmentoMapInfo(
            segmento: segmento,
            actividad: actividad,
            points: segmento.ubicacionGis,
            color: color,
            centroid: _computeCentroid(segmento.ubicacionGis),
          ));
        }
      }
      actividadesSegmentos.assignAll(segmentos);
    } catch (e) {
      errorActividades.value = 'Error cargando actividades';
      debugPrint('MapaGlobal actividades: $e');
    } finally {
      isLoadingActividades.value = false;
    }
  }

  void zoomIn() {
    final cam = mapController.camera;
    mapController.move(cam.center, (cam.zoom + 1).clamp(5, 20));
  }

  void zoomOut() {
    final cam = mapController.camera;
    mapController.move(cam.center, (cam.zoom - 1).clamp(5, 20));
  }

  void navigateToSegmento(SegmentoEntity segmento) {
    Get.offAndToNamed(AppRoutes.detalle, arguments: segmento);
  }

  void _fitAllBounds() {
    final allPoints = <LatLng>[
      ...gasoductosPolylines.expand((p) => p.points),
      ...actividadesSegmentos.expand((s) => s.points),
    ];
    if (allPoints.isEmpty) return;

    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;

    for (final p in allPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    try {
      mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(minLat, minLng),
            LatLng(maxLat, maxLng),
          ),
          padding: const EdgeInsets.all(40),
        ),
      );
    } catch (_) {}
  }

  LatLng _computeCentroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(40.4168, -3.7038);
    return points[points.length ~/ 2];
  }
}
