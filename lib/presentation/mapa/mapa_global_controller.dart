import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_di.dart';
import '../../core/app_theme.dart';
import '../../core/services/gasoductos_service.dart';
import '../../core/services/gps_background_service.dart';
import '../../core/services/pks_service.dart';
import '../../core/services/hitos_service.dart';
import '../../data/repository/segmento_repository_impl.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/entities/user_entity.dart';
import 'layers/posiciones_fijas_map_controller.dart';
import 'layers/segmentos_map_controller.dart';
import 'lines_cut/lines_cut_controller.dart';
import 'lines_cut/lines_cut_dialog.dart';

class MapaGlobalController extends GetxController {
  final mapController = MapController();

  late final LinesCutController linesCut;

  final gasoductosPolylines = <Polyline>[].obs;
  final isLoadingGasoductos = false.obs;
  final isLoadingPks = false.obs;
  final isLoadingHitos = false.obs;
  final errorGasoductos = Rx<String?>(null);
  final errorPks = Rx<String?>(null);
  final errorHitos = Rx<String?>(null);
  final currentZoom = 0.0.obs;

  GasoductosService get _gasoductosService => AppDI.gasoductosService;
  PksService get _pksService => AppDI.pksService;
  HitosService get _hitosService => AppDI.hitosService;
  SegmentosMapController get _segmentos => Get.find<SegmentosMapController>();
  PosicionesFijasMapController get _posicionesFijas =>
      Get.find<PosicionesFijasMapController>();

  final _segmentoRepo = SegmentoRepositoryImpl();

  bool get isLoading =>
      isLoadingGasoductos.value ||
      isLoadingPks.value ||
      isLoadingHitos.value ||
      _segmentos.isLoading.value ||
      _posicionesFijas.isLoading.value;

  List<({String ct, int ctid})> _userCts = const [];

  Future<void> _loadUserCts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('user_json');
      if (raw == null) {
        _userCts = const [];
        return;
      }
      final user = UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _userCts = user.cts.map((c) => (ct: c.ct, ctid: c.ctid)).toList();
    } catch (_) {
      _userCts = const [];
    }
  }

  @override
  void onInit() {
    super.onInit();
    linesCut = LinesCutController(
      visiblePolylinesProvider: visibleGasoductoPolylines,
      ctsProvider: () => _userCts,
    );
    Get.put<LinesCutController>(linesCut);
    gasoductosPolylines.assignAll(_gasoductosService.polylines);
    ever(_gasoductosService.polylines,
        (List<Polyline> lines) => gasoductosPolylines.assignAll(lines));
    _loadUserCts();
    _loadSavedView();
    loadAll();
    unawaited(DI.get<GpsBackgroundService>().start());
  }

  /// NF-8: awaitable stop — call from PopScope/route exit handler so the
  /// final GPS flush completes before the page is disposed.
  /// [onClose] also calls stop() unawaited as a safety net.
  Future<void> stopTracking() =>
      DI.get<GpsBackgroundService>().stop();

  @override
  void onClose() {
    _saveDebounce?.cancel();
    if (Get.isRegistered<LinesCutController>()) {
      Get.delete<LinesCutController>();
    }
    // Safety net: if stopTracking() was not awaited by the PopScope handler,
    // this ensures the service is stopped (non-awaited, best-effort).
    unawaited(DI.get<GpsBackgroundService>().stop());
    super.onClose();
  }

  // ─────────────────── Persistencia de la vista del mapa ───────────────────

  static const _kMapLastLat = 'mapa_global_last_lat';
  static const _kMapLastLng = 'mapa_global_last_lng';
  static const _kMapLastZoom = 'mapa_global_last_zoom';

  LatLng? _savedCenter;
  double? _savedZoom;
  bool _viewRestored = false;
  bool _mapReady = false;
  Timer? _saveDebounce;

  Future<void> _loadSavedView() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_kMapLastLat);
      final lng = prefs.getDouble(_kMapLastLng);
      final zoom = prefs.getDouble(_kMapLastZoom);
      if (lat != null && lng != null && zoom != null) {
        _savedCenter = LatLng(lat, lng);
        _savedZoom = zoom;
        if (_mapReady) _restoreSavedView();
      }
    } catch (_) {}
  }

  void _restoreSavedView() {
    final c = _savedCenter;
    final z = _savedZoom;
    if (c == null || z == null) return;
    try {
      mapController.move(c, z);
      _viewRestored = true;
    } catch (_) {}
  }

  void onMapReady() {
    _mapReady = true;
    if (_savedCenter != null && _savedZoom != null) _restoreSavedView();
  }

  void _persistViewDebounced() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final cam = mapController.camera;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(_kMapLastLat, cam.center.latitude);
        await prefs.setDouble(_kMapLastLng, cam.center.longitude);
        await prefs.setDouble(_kMapLastZoom, cam.zoom);
      } catch (_) {}
    });
  }

  // ─────────────────── Eventos del mapa ────────────────────────────────────

  void onMapEvent(MapEvent event) {
    final z = mapController.camera.zoom;
    if (currentZoom.value != z) currentZoom.value = z;
    linesCut.updateZoom(z);
    _persistViewDebounced();
  }

  void onMapTap(TapPosition tapPosition, LatLng point) {
    if (linesCut.canCut.value) linesCut.addPoint(point);
  }

  List<Polyline> visibleGasoductoPolylines() {
    final bounds = mapController.camera.visibleBounds;
    return gasoductosPolylines
        .where((p) => p.points.any((pt) => bounds.contains(pt)))
        .toList(growable: false);
  }

  // ─────────────────── Zoom ────────────────────────────────────────────────

  void zoomIn() {
    final cam = mapController.camera;
    final z = (cam.zoom + 0.25).clamp(5.0, 20.0);
    mapController.move(cam.center, z);
    currentZoom.value = z;
  }

  void zoomOut() {
    final cam = mapController.camera;
    final z = (cam.zoom - 0.25).clamp(5.0, 20.0);
    mapController.move(cam.center, z);
    currentZoom.value = z;
  }

  // ─────────────────── Carga de datos ──────────────────────────────────────

  Future<void> loadAll() async {
    await loadGasoductos();
    await loadPks();
    await loadHitos();
    await _segmentos.load();
    await _posicionesFijas.load();
    _fitAllBounds();
  }

  Future<void> reloadAll() async {
    await loadGasoductos(forceRefresh: true);
    await loadPks(forceRefresh: true);
    await loadHitos(forceRefresh: true);
    await _segmentos.load();
    await _posicionesFijas.load();
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
    } catch (e) {
      errorPks.value = 'Error cargando PKs';
      debugPrint('MapaGlobal PKs: $e');
    } finally {
      isLoadingPks.value = false;
    }
  }

  Future<void> loadHitos({bool forceRefresh = false}) async {
    isLoadingHitos.value = true;
    errorHitos.value = null;
    try {
      if (forceRefresh) {
        await _hitosService.reload();
      } else {
        await _hitosService.ensureLoaded();
      }
    } catch (e) {
      errorHitos.value = 'Error cargando hitos';
      debugPrint('MapaGlobal Hitos: $e');
    } finally {
      isLoadingHitos.value = false;
    }
  }

  // ─────────────────── Líneas de corte ─────────────────────────────────────

  Future<void> applyLinesCut() async {
    final raw = linesCut.applyCut();
    if (raw.isEmpty) {
      Get.snackbar(
        'Sin resultados',
        'Las líneas no cruzan ningún gasoducto visible.',
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
      );
      return;
    }

    final totalMeters = raw.fold<double>(0, (s, seg) => s + seg.lengthInMeters);
    final first = raw.first;

    final dlg = await showLinesCutCaptureDialog(
      headerTitle: 'Nuevo segmento de corte',
      headerSubtitle: first.name,
      totalMeters: totalMeters,
      totalSquareMeters: totalMeters * 4,
    );

    if (dlg == null) return;

    linesCut.applyDialogToExtracted(
      descripcion: dlg.descripcion,
      tipoActividad: dlg.tipoActividad,
      estado: dlg.estado,
    );

    final nuevos = <SegmentoMapInfo>[];
    for (final seg in raw) {
      final entity = SegmentoEntity.empty()
        ..ubicacionGis = seg.points
        ..latInicio = seg.points.first.latitude
        ..lngInicio = seg.points.first.longitude
        ..latFin = seg.points.last.latitude
        ..lngFin = seg.points.last.longitude
        ..ctId = seg.ctId
        ..traza = seg.traza
        ..descripcion = seg.description
        ..tipoActividad = seg.tipoActividad
        ..estado = seg.estado;
      final persisted = await _segmentoRepo.insertLocalOnly(entity);
      nuevos.add(SegmentoMapInfo(
        segmento: persisted,
        points: persisted.ubicacionGis,
        color: AppColors.accentForEstado(persisted.estado),
        centroid: _segmentos.centroid(persisted.ubicacionGis),
      ));
    }
    _segmentos.segmentos.addAll(nuevos);

    linesCut.clearAll();
    linesCut.clearExtracted();
    linesCut.canCut.value = false;
    linesCut.cutStateOn.value = false;
  }

  // ─────────────────── Helpers ──────────────────────────────────────────────

  void _fitAllBounds() {
    if (_viewRestored) return;

    final allPoints = <LatLng>[
      ...gasoductosPolylines.expand((p) => p.points),
      ..._segmentos.segmentos.expand((s) => s.points),
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
}
