import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:helireport_desherbaje/core/my_getx_controller.dart';
import '../../core/app_log.dart';
import '../../core/app_router.dart';
import '../../core/result/data_result.dart';
import '../../core/screen_state.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/usecases/get_segmentos_usecase.dart';

class SegmentosListController extends MyGetxController {
  SegmentosListController(this._useCase);

  final GetSegmentosUseCase _useCase;

  final segmentos = <SegmentoEntity>[].obs;
  final filtradas = <SegmentoEntity>[].obs;
  final isLoading = false.obs;
  final error = Rx<String?>(null);
  final selectedEstado = Rx<EstadoActividad?>(null);
  final selectedTipo = Rx<TipoActividad?>(null);
  final selectedCt = Rx<String?>(null);
  final filterDescripcion = ''.obs;

  /// CT cuya tarjeta de grupo está expandida en el acordeón. `null` colapsa
  /// todos. Se identifica por NOMBRE de CT (§3/§8). Se inicializa al primer CT
  /// con resultados al cargar.
  final expandedCt = Rx<String?>(null);

  /// Controla el `TextField` de descripción: el filtro restaurado tiene que
  /// verse en la caja, no solo aplicarse.
  final descripcionCtrl = TextEditingController();

  final _state = ScreenState('segmentos_list');

  @override
  void myOnInit() {
    addWorker(debounce(
      filterDescripcion,
      (_) => _applyFilter(),
      time: const Duration(milliseconds: 300),
    ));
    // Restaurar ANTES de cargar: `loadSegmentos` aplica filtros y fija el CT
    // expandido, así que si la restauración llegara después pisaría lo leído
    // o sería pisada por el valor por defecto.
    unawaited(_restoreState().then((_) => loadSegmentos()));
  }

  @override
  void onClose() {
    _state.dispose();
    descripcionCtrl.dispose();
    super.onClose();
  }

  // ─────────────────── Persistencia del estado de pantalla ───────────────────

  Future<void> _restoreState() async {
    await _state.load();
    final estadoName = _state.text('estado');
    if (estadoName != null) {
      selectedEstado.value = _parseEnum(EstadoActividad.values, estadoName);
      if (selectedEstado.value == null) {
        AppLog.w('SegmentosListController: estado guardado desconocido '
            '"$estadoName", se ignora');
      }
    }
    final tipoName = _state.text('tipo');
    if (tipoName != null) {
      selectedTipo.value = _parseEnum(TipoActividad.values, tipoName);
      if (selectedTipo.value == null) {
        AppLog.w('SegmentosListController: tipo guardado desconocido '
            '"$tipoName", se ignora');
      }
    }
    selectedCt.value = _state.text('ct');
    expandedCt.value = _state.text('expanded_ct');
    final descripcion = _state.text('descripcion') ?? '';
    descripcionCtrl.text = descripcion;
    // Asignación directa: pasar por `filterDescripcion` dispararía el debounce
    // y un `_applyFilter` extra antes de que haya datos cargados.
    filterDescripcion.value = descripcion;
  }

  /// Guarda todo el estado junto: `save()` es un debounce único, así que un
  /// snapshot parcial por setter perdería los cambios encadenados.
  void _persistState() {
    _state.save(() => {
          'estado': selectedEstado.value?.name,
          'tipo': selectedTipo.value?.name,
          'ct': selectedCt.value,
          'descripcion':
              filterDescripcion.value.isEmpty ? null : filterDescripcion.value,
          'expanded_ct': expandedCt.value,
        });
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

  /// Etiqueta legible del CT. El nombre viaja en la propia entidad (§3/§8);
  /// cae a 'CT desconocido' si viniera vacío.
  String ctLabel(String ctname) =>
      ctname.isNotEmpty ? ctname : 'CT desconocido';

  Future<void> loadSegmentos() async {
    isLoading.value = true;
    error.value = null;
    final result = await _useCase.execute();
    switch (result) {
      case DataSuccess(:final data):
        segmentos.assignAll(data);
        _applyFilter();
        _ensureExpanded();
      case DataFailure(:final message):
        error.value = message;
    }
    isLoading.value = false;
  }

  void filterByEstado(EstadoActividad? estado) {
    selectedEstado.value = estado;
    _applyFilter();
  }

  void filterByTipo(TipoActividad? tipo) {
    selectedTipo.value = tipo;
    _applyFilter();
  }

  void filterByCt(String? ctname) {
    selectedCt.value = ctname;
    _applyFilter();
  }

  /// Nombres de CT presentes en los segmentos cargados, ordenados alfabéticamente.
  List<String> get ctsDisponibles {
    final names = segmentos.map((s) => s.ctname).toSet().toList();
    names.sort((a, b) => ctLabel(a).compareTo(ctLabel(b)));
    return names;
  }

  void toggleCtExpanded(String ctname) {
    expandedCt.value = expandedCt.value == ctname ? null : ctname;
    _persistState();
  }

  /// Mapa CT → segmentos, para el render agrupado. La clave es el nombre de CT.
  Map<String, List<SegmentoEntity>> get groupedByCt {
    final map = <String, List<SegmentoEntity>>{};
    for (final s in filtradas) {
      map.putIfAbsent(s.ctname, () => []).add(s);
    }
    return map;
  }

  void _applyFilter() {
    final query = filterDescripcion.value.trim().toLowerCase();
    final estado = selectedEstado.value;
    final tipo = selectedTipo.value;
    final ct = selectedCt.value;

    filtradas.assignAll(segmentos.where((s) {
      // Los segmentos finalizados no aparecen en el listado del operario:
      // ya no hay acción que tomar sobre ellos.
      if (s.estado == EstadoActividad.finalizada) return false;
      if (estado != null && s.estado != estado) return false;
      if (tipo != null && s.tipoActividad != tipo) return false;
      if (ct != null && s.ctname != ct) return false;
      if (query.isNotEmpty && !s.descripcion.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }));
    _ensureExpanded();
    // Un solo punto de guardado: todos los setters de filtro y el debounce de
    // descripción pasan por aquí, y así se persiste también la corrección de
    // `_ensureExpanded` cuando el CT guardado ya no tiene resultados.
    _persistState();
  }

  void _ensureExpanded() {
    if (filtradas.isEmpty) return;
    final ctNames = filtradas.map((s) => s.ctname).toSet();
    if (expandedCt.value == null || !ctNames.contains(expandedCt.value)) {
      expandedCt.value = ctNames.first;
    }
  }

  /// Al volver del detalle se recarga desde SQLite: el segmento puede haberse
  /// editado o eliminado allí, y la lista en memoria quedaría obsoleta.
  void goToDetalle(SegmentoEntity segmento) {
    Get.toNamed(AppRoutes.detalle, arguments: segmento)
        ?.then((_) => loadSegmentos());
  }
}
