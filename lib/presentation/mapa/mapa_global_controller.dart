import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../core/services/gasoductos_service.dart';
import '../../core/services/pks_service.dart';
import '../../data/repository/segmento_repository_impl.dart';
import '../../domain/entities/pk_entity.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/usecases/get_segmentos_usecase.dart';

class SegmentoMapInfo {
  final SegmentoEntity segmento;
  final List<LatLng> points;
  final Color color;
  final LatLng centroid;

  const SegmentoMapInfo({
    required this.segmento,
    required this.points,
    required this.color,
    required this.centroid,
  });
}

class MapaGlobalController extends GetxController {
  final mapController = MapController();

  final gasoductosPolylines = <Polyline>[].obs;
  final segmentos = <SegmentoMapInfo>[].obs;
  final pks = <PkEntity>[].obs;
  final isLoadingGasoductos = false.obs;
  final isLoadingSegmentos = false.obs;
  final isLoadingPks = false.obs;
  final errorGasoductos = Rx<String?>(null);
  final errorSegmentos = Rx<String?>(null);
  final errorPks = Rx<String?>(null);
  final currentZoom = 0.0.obs;

  // ──────────────────────────── Filtros ────────────────────────────
  final rxEstado = Rx<EstadoActividad?>(null);
  final rxTipo = Rx<TipoActividad?>(null);

  void setEstado(EstadoActividad? value) => rxEstado.value = value;
  void setTipo(TipoActividad? value) => rxTipo.value = value;

  /// Subconjunto de [segmentos] tras aplicar los filtros activos. Se usa
  /// tanto para pintar las polylines como para los marcadores con etiqueta.
  List<SegmentoMapInfo> get filteredSegmentos {
    final estado = rxEstado.value;
    final tipo = rxTipo.value;
    if (estado == null && tipo == null) return segmentos.toList();
    return segmentos.where((info) {
      if (estado != null && info.segmento.estado != estado) return false;
      if (tipo != null && info.segmento.tipoActividad != tipo) return false;
      return true;
    }).toList();
  }

  void onMapEvent(MapEvent event) {
    // Sync con cualquier evento de cámara — pinch, doble-tap, fling y
    // movimientos programáticos también deben refrescar el zoom para que las
    // capas dependientes (PKs, labels) reaccionen.
    final z = mapController.camera.zoom;
    if (currentZoom.value != z) currentZoom.value = z;
  }

  late final GetSegmentosUseCase _segmentosUseCase;
  GasoductosService get _gasoductosService => Get.find<GasoductosService>();
  PksService get _pksService => Get.find<PksService>();

  bool get isLoading =>
      isLoadingGasoductos.value ||
      isLoadingSegmentos.value ||
      isLoadingPks.value;

  @override
  void onInit() {
    super.onInit();
    _segmentosUseCase = GetSegmentosUseCase(SegmentoRepositoryImpl());
    ever(_gasoductosService.polylines,
        (lines) => gasoductosPolylines.assignAll(lines));
    ever(_pksService.pks, (entities) => pks.assignAll(entities));
    loadAll();
  }

  Future<void> loadAll() async {
    // Secuencial: el `JsonLoaderService` serializa internamente, pero los
    // eventos completed son broadcast — encadenar evita ambigüedad.
    await loadGasoductos();
    await loadPks();
    await loadSegmentos();
    _fitAllBounds();
  }

  Future<void> reloadAll() async {
    await loadGasoductos(forceRefresh: true);
    await loadPks(forceRefresh: true);
    await loadSegmentos();
    _fitAllBounds();
  }

  Future<void> reloadSegmentos() async {
    await loadSegmentos();
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

  Future<void> loadPks({bool forceRefresh = false}) async {
    isLoadingPks.value = true;
    errorPks.value = null;
    try {
      if (forceRefresh) {
        await _pksService.reload();
      } else {
        await _pksService.ensureLoaded();
      }
      pks.assignAll(_pksService.pks);
    } catch (e) {
      errorPks.value = 'Error cargando PKs';
      debugPrint('MapaGlobal PKs: $e');
    } finally {
      isLoadingPks.value = false;
    }
  }

  Future<void> loadSegmentos() async {
    isLoadingSegmentos.value = true;
    errorSegmentos.value = null;
    try {
      final result = await _segmentosUseCase.execute();
      if (result.isFailure) {
        errorSegmentos.value = 'Error cargando Segmentos';
        return;
      }
      final fetched = result.dataOrNull ?? <SegmentoEntity>[];
      final mapped = <SegmentoMapInfo>[];
      for (final segmento in fetched) {
        if (segmento.ubicacionGis.isEmpty) continue;
        mapped.add(SegmentoMapInfo(
          segmento: segmento,
          points: segmento.ubicacionGis,
          color: AppColors.accentForEstado(segmento.estado),
          centroid: _computeCentroid(segmento.ubicacionGis),
        ));
      }
      segmentos.assignAll(mapped);
    } catch (e) {
      errorSegmentos.value = 'Error cargando Segmentos';
      debugPrint('MapaGlobal Segmentos: $e');
    } finally {
      isLoadingSegmentos.value = false;
    }
  }

  void zoomIn() {
    final cam = mapController.camera;
    final z = (cam.zoom + 1).clamp(5.0, 20.0);
    mapController.move(cam.center, z);
    currentZoom.value = z;
  }

  void zoomOut() {
    final cam = mapController.camera;
    final z = (cam.zoom - 1).clamp(5.0, 20.0);
    mapController.move(cam.center, z);
    currentZoom.value = z;
  }

  void navigateToSegmento(SegmentoEntity segmento) {
    Get.offAndToNamed(AppRoutes.detalle, arguments: segmento);
  }

  void _fitAllBounds() {
    final allPoints = <LatLng>[
      ...gasoductosPolylines.expand((p) => p.points),
      ...segmentos.expand((s) => s.points),
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
