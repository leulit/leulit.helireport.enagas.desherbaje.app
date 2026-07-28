import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/app_log.dart';
import '../../../core/app_router.dart';
import '../../../core/app_theme.dart';
import '../../../core/my_getx_controller.dart';
import '../../../core/screen_state.dart';
import '../../../data/repository/segmento_repository_impl.dart';
import '../../../domain/entities/segmento_entity.dart';
import '../../../domain/usecases/get_segmentos_usecase.dart';
import '../lines_cut/lines_cut_controller.dart';

class SegmentoMapInfo {
  final SegmentoEntity segmento;
  final List<LatLng> points;
  final Color color;
  final LatLng centroid;

  /// Longitud precalculada (km) — evita recorrer `points` con haversine par a
  /// par en cada build de la etiqueta (antes: `segmento.longitudKm`, un
  /// getter sin caché llamado por label y por frame).
  final double longitudKm;

  const SegmentoMapInfo({
    required this.segmento,
    required this.points,
    required this.color,
    required this.centroid,
    required this.longitudKm,
  });
}

class SegmentosMapController extends MyGetxController {
  final _segmentosUseCase = GetSegmentosUseCase(SegmentoRepositoryImpl());

  final segmentosHitNotifier = LayerHitNotifier<SegmentoEntity>(null);
  final segmentos = <SegmentoMapInfo>[].obs;
  final isLoading = false.obs;
  final error = Rx<String?>(null);

  /// Visibilidad de la barra de filtros. Se oculta al entrar en modo
  /// corte de líneas (reactividad con primitiva Flutter, no `.obs`).
  final filtrosVisible = ValueNotifier<bool>(true);

  final rxEstado = Rx<EstadoActividad?>(null);
  final rxTipo = Rx<TipoActividad?>(null);
  final rxCt = Rx<String?>(null);

  /// Se incrementa cada vez que cambia cualquier filtro (estado/tipo/ct) o se
  /// recarga `segmentos`. Es el ÚNICO observable que necesita leer la capa
  /// para invalidar su pintado — así el `ValueListenableBuilder` de
  /// polilíneas reacciona también al filtro de CT (antes el `Obx` solo leía
  /// `rxEstado`/`rxTipo` y el cambio de CT no repintaba las líneas, aunque
  /// `filteredSegmentos` sí filtraba por CT). `ValueNotifier`, no `.obs`:
  /// reactividad nueva va con primitivas Flutter (CLAUDE.md).
  final filterVersion = ValueNotifier<int>(0);

  List<SegmentoMapInfo>? _filteredCache;

  /// Invalida la caché de [filteredSegmentos]. Público porque
  /// `MapaGlobalController.applyLinesCut` añade segmentos directamente a
  /// [segmentos] (fuera de [load]) al confirmar un corte de líneas.
  void invalidateFilterCache() => _invalidateFilterCache();

  void _invalidateFilterCache() {
    _filteredCache = null;
    filterVersion.value++;
  }

  final _state = ScreenState('mapa_segmentos');

  void setEstado(EstadoActividad? v) {
    rxEstado.value = v;
    _invalidateFilterCache();
    _persistFiltros();
  }

  void setTipo(TipoActividad? v) {
    rxTipo.value = v;
    _invalidateFilterCache();
    _persistFiltros();
  }

  void setCt(String? v) {
    rxCt.value = v;
    _invalidateFilterCache();
    _persistFiltros();
  }

  /// Guarda los tres filtros juntos: `save()` es un debounce único, así que un
  /// snapshot parcial por setter perdería los cambios encadenados.
  void _persistFiltros() {
    _state.save(() => {
          'estado': rxEstado.value?.name,
          'tipo': rxTipo.value?.name,
          'ct': rxCt.value,
        });
  }

  /// Etiqueta legible del CT. El nombre viaja en la propia entidad (§3/§8);
  /// cae a 'CT desconocido' si viniera vacío.
  String ctLabel(String ctname) =>
      ctname.isNotEmpty ? ctname : 'CT desconocido';

  /// Nombres de CT presentes en los segmentos cargados, ordenados alfabéticamente.
  List<String> get ctsDisponibles {
    final names = segmentos.map((i) => i.segmento.ctname).toSet().toList();
    names.sort((a, b) => ctLabel(a).compareTo(ctLabel(b)));
    return names;
  }

  /// Lista filtrada, cacheada: recorrer y copiar `segmentos` es caro y esta
  /// lista se evalúa dos veces por rebuild de la capa (polilíneas + labels).
  /// Se invalida en `_invalidateFilterCache` (setters de filtro) y en `load`.
  List<SegmentoMapInfo> get filteredSegmentos {
    final cached = _filteredCache;
    if (cached != null) return cached;
    final estado = rxEstado.value;
    final tipo = rxTipo.value;
    final ct = rxCt.value;
    final result = (estado == null && tipo == null && ct == null)
        ? segmentos.toList()
        : segmentos.where((info) {
            if (estado != null && info.segmento.estado != estado) return false;
            if (tipo != null && info.segmento.tipoActividad != tipo) return false;
            if (ct != null && info.segmento.ctname != ct) return false;
            return true;
          }).toList();
    _filteredCache = result;
    return result;
  }

  @override
  void myOnInit() {
    onTypedAction(LinesCutTypedActions.startCutAction, (action) {
      filtrosVisible.value = false;
    });
    onTypedAction(LinesCutTypedActions.endCutAction, (action) {
      filtrosVisible.value = true;
    });
    unawaited(_restoreFiltros());
  }

  Future<void> _restoreFiltros() async {
    await _state.load();
    final estadoName = _state.text('estado');
    if (estadoName != null) {
      rxEstado.value = _parseEnum(EstadoActividad.values, estadoName);
      if (rxEstado.value == null) {
        AppLog.w('SegmentosMapController: estado guardado desconocido '
            '"$estadoName", se ignora');
      }
    }
    final tipoName = _state.text('tipo');
    if (tipoName != null) {
      rxTipo.value = _parseEnum(TipoActividad.values, tipoName);
      if (rxTipo.value == null) {
        AppLog.w('SegmentosMapController: tipo guardado desconocido '
            '"$tipoName", se ignora');
      }
    }
    rxCt.value = _state.text('ct');
    _invalidateFilterCache();
  }

  /// Parse tolerante de un enum por `.name`: si no matchea ningún valor
  /// (p.ej. cambió el catálogo entre versiones), devuelve `null` en lugar de
  /// lanzar.
  T? _parseEnum<T extends Enum>(List<T> values, String name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  Future<void> load() async {
    isLoading.value = true;
    error.value = null;
    try {
      final result = await _segmentosUseCase.execute();
      if (result.isFailure) {
        error.value = 'Error cargando Segmentos';
        return;
      }
      final fetched = result.dataOrNull ?? <SegmentoEntity>[];
      final mapped = <SegmentoMapInfo>[];
      for (final s in fetched) {
        if (s.ubicacionGis.isEmpty) continue;
        mapped.add(SegmentoMapInfo(
          segmento: s,
          points: s.ubicacionGis,
          color: AppColors.accentForEstado(s.estado),
          centroid: _centroid(s.ubicacionGis),
          longitudKm: s.longitudKm,
        ));
      }
      segmentos.assignAll(mapped);
      _invalidateFilterCache();
    } catch (e) {
      error.value = 'Error cargando Segmentos';
      debugPrint('SegmentosMapController: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void onPolylineTap() {
    final hit = segmentosHitNotifier.value;
    if (hit == null || hit.hitValues.isEmpty) return;
    navigateToSegmento(hit.hitValues.first);
  }

  void navigateToSegmento(SegmentoEntity segmento) {
    Get.offAndToNamed(AppRoutes.detalle, arguments: segmento);
  }

  LatLng centroid(List<LatLng> points) => _centroid(points);

  LatLng _centroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(40.4168, -3.7038);
    return points[points.length ~/ 2];
  }

  @override
  void onClose() {
    _state.dispose();
    segmentosHitNotifier.dispose();
    filtrosVisible.dispose();
    filterVersion.dispose();
    super.onClose();
  }
}
