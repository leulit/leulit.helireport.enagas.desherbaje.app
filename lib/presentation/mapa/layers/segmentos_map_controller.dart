import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/app_router.dart';
import '../../../core/app_theme.dart';
import '../../../core/my_getx_controller.dart';
import '../../../data/repository/segmento_repository_impl.dart';
import '../../../domain/entities/segmento_entity.dart';
import '../../../domain/usecases/get_segmentos_usecase.dart';
import '../lines_cut/lines_cut_controller.dart';

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

  void setEstado(EstadoActividad? v) => rxEstado.value = v;
  void setTipo(TipoActividad? v) => rxTipo.value = v;
  void setCt(String? v) => rxCt.value = v;

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

  List<SegmentoMapInfo> get filteredSegmentos {
    final estado = rxEstado.value;
    final tipo = rxTipo.value;
    final ct = rxCt.value;
    if (estado == null && tipo == null && ct == null) return segmentos.toList();
    return segmentos.where((info) {
      if (estado != null && info.segmento.estado != estado) return false;
      if (tipo != null && info.segmento.tipoActividad != tipo) return false;
      if (ct != null && info.segmento.ctname != ct) return false;
      return true;
    }).toList();
  }

  @override
  void myOnInit() {
    onTypedAction(LinesCutTypedActions.startCutAction, (action) {
      filtrosVisible.value = false;
    });
    onTypedAction(LinesCutTypedActions.endCutAction, (action) {
      filtrosVisible.value = true;
    });
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
        ));
      }
      segmentos.assignAll(mapped);
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
    segmentosHitNotifier.dispose();
    filtrosVisible.dispose();
    super.onClose();
  }
}
