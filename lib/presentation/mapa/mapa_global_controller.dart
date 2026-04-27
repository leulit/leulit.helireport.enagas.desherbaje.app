import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../core/services/gasoductos_service.dart';
import '../../core/services/gps_background_service.dart';
import '../../core/services/pks_service.dart';
import '../../data/repository/segmento_repository_impl.dart';
import '../../domain/entities/pk_entity.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/usecases/get_segmentos_usecase.dart';
import 'lines_cut/lines_cut_controller.dart';
import 'lines_cut/lines_cut_dialog.dart';

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

  /// Controller de la feature "Líneas de corte" (ver
  /// `presentation/mapa/lines_cut/`). Se instancia aquí en lugar de en el
  /// Binding porque necesita cerrar sobre `visiblePolylinesProvider`.
  late final LinesCutController linesCut;

  /// Notifier usado por el `PolylineLayer` de segmentos para hit-testing.
  /// Cuando el usuario toca una polyline, su `hitValue` (la `SegmentoEntity`
  /// asociada) queda disponible en `segmentosHitNotifier.value.hitValues`.
  final segmentosHitNotifier = LayerHitNotifier<SegmentoEntity>(null);

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
    linesCut.updateZoom(z);
    _persistViewDebounced();
  }

  /// Ruta del `onTap` del mapa. Si la feature de corte está en modo dibujo,
  /// cada tap añade un punto a la línea activa.
  void onMapTap(TapPosition tapPosition, LatLng point) {
    if (linesCut.canCut.value) {
      linesCut.addPoint(point);
    }
  }

  /// Filtra las polylines de gasoducto por el viewport actual para acotar
  /// el O(N·M) del motor de corte al área visible.
  List<Polyline> visibleGasoductoPolylines() {
    final bounds = mapController.camera.visibleBounds;
    return gasoductosPolylines
        .where((p) =>
            p.points.any((pt) => bounds.contains(pt)))
        .toList(growable: false);
  }

  /// Cache en memoria de los CTs del usuario logueado. Se rellena en
  /// [onInit] tras leer `user_json` de prefs. El [LinesCutController] lo
  /// lee por referencia de forma síncrona al resolver ctId.
  List<({String ct, int ctid})> _userCts = const [];

  Future<void> _loadUserCts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('user_json');
      if (raw == null) {
        _userCts = const [];
        return;
      }
      final user =
          UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _userCts = user.cts.map((c) => (ct: c.ct, ctid: c.ctid)).toList();
    } catch (_) {
      _userCts = const [];
    }
  }

  late final GetSegmentosUseCase _segmentosUseCase;
  final _segmentoRepo = SegmentoRepositoryImpl();
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
    linesCut = LinesCutController(
      visiblePolylinesProvider: visibleGasoductoPolylines,
      ctsProvider: () => _userCts,
    );
    Get.put<LinesCutController>(linesCut);
    // Captura el estado actual de los servicios antes de enganchar `ever()`:
    // si los datos ya estaban cargados (p. ej. tras un `reload()` desde la
    // sync page) el listener no recibirá ninguna emisión y la primera
    // asignación se perdería.
    gasoductosPolylines.assignAll(_gasoductosService.polylines);
    pks.assignAll(_pksService.pks);
    ever(_gasoductosService.polylines,
        (List<Polyline> lines) => gasoductosPolylines.assignAll(lines));
    ever(_pksService.pks,
        (List<PkEntity> entities) => pks.assignAll(entities));
    _loadUserCts();
    _loadSavedView();
    loadAll();
    // GPS tracking lifecycle is bound to this screen (decision P15+P16):
    // start when entering the map, stop on close.
    unawaited(Get.find<GpsBackgroundService>().start());
  }

  @override
  void onClose() {
    _saveDebounce?.cancel();
    segmentosHitNotifier.dispose();
    if (Get.isRegistered<LinesCutController>()) {
      Get.delete<LinesCutController>();
    }
    unawaited(Get.find<GpsBackgroundService>().stop());
    super.onClose();
  }

  // ─────────────────── Persistencia de la vista del mapa ───────────────────
  // Guardamos center + zoom en SharedPreferences para que al volver a la
  // página el usuario aterrice en el mismo viewport que dejó.
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
        // Si el mapa ya estaba listo (carrera prefs/build), aplicamos ya.
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

  /// Llamado desde `MapOptions.onMapReady` en la página. A partir de aquí el
  /// `MapController` ya tiene cámara válida y se puede mover.
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

  /// Invocado desde el `GestureDetector` que envuelve el `PolylineLayer` de
  /// segmentos. Si el tap impactó en alguna polyline, navega al detalle del
  /// primer segmento bajo el dedo (mismo flujo que el tap en el label).
  void onSegmentoPolylineTap() {
    final hit = segmentosHitNotifier.value;
    if (hit == null || hit.hitValues.isEmpty) return;
    navigateToSegmento(hit.hitValues.first);
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

  void navigateToSegmento(SegmentoEntity segmento) {
    Get.offAndToNamed(AppRoutes.detalle, arguments: segmento);
  }

  /// Aplica el corte actual: ejecuta el motor, abre el diálogo de captura
  /// y, si se confirma, navega al detalle del primer segmento resultante
  /// (mismo patrón que [navigateToSegmento]). Al terminar limpia líneas;
  /// si el usuario cancela las deja intactas para reintentar.
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

    final totalMeters =
        raw.fold<double>(0, (s, seg) => s + seg.lengthInMeters);
    final first = raw.first;

    final dlg = await showLinesCutCaptureDialog(
      headerTitle: 'Nuevo segmento de corte',
      headerSubtitle: first.name,
      totalMeters: totalMeters,
      totalSquareMeters: totalMeters * 4,
    );

    if (dlg == null) return; // usuario canceló — líneas se conservan

    linesCut.applyDialogToExtracted(
      descripcion: dlg.descripcion,
      tipoActividad: dlg.tipoActividad,
      estado: dlg.estado,
    );

    // Cada segmento extraído se persiste en SQLite como "local-only"
    // (id negativo, needs_sync=1) para que sobreviva a la navegación y
    // aparezca también en el listado agrupado por CT. Paralelamente lo
    // añadimos en memoria al mapa para feedback inmediato sin recargar.
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
        centroid: _computeCentroid(persisted.ubicacionGis),
      ));
    }
    segmentos.addAll(nuevos);

    linesCut.clearAll();
    linesCut.clearExtracted();
    linesCut.canCut.value = false;
    linesCut.cutStateOn.value = false;
  }

  void _fitAllBounds() {
    // Si ya restauramos la vista guardada del usuario, no pisamos su
    // posición/zoom con el fit automático de los datos.
    if (_viewRestored) return;

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
