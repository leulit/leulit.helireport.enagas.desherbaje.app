import 'package:get/get.dart';
import 'package:helireport_desherbaje/core/my_getx_controller.dart';
import '../../core/app_router.dart';
import '../../core/result/data_result.dart';
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
  final filterDescripcion = ''.obs;

  /// CT cuya tarjeta de grupo está expandida en el acordeón. `null` colapsa
  /// todos. Se identifica por NOMBRE de CT (§3/§8). Se inicializa al primer CT
  /// con resultados al cargar.
  final expandedCt = Rx<String?>(null);

  @override
  void myOnInit() {
    debounce(
      filterDescripcion,
      (_) => _applyFilter(),
      time: const Duration(milliseconds: 300),
    );
    loadSegmentos();
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

  void toggleCtExpanded(String ctname) {
    expandedCt.value = expandedCt.value == ctname ? null : ctname;
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

    filtradas.assignAll(segmentos.where((s) {
      // Los segmentos finalizados no aparecen en el listado del operario:
      // ya no hay acción que tomar sobre ellos.
      if (s.estado == EstadoActividad.finalizada) return false;
      if (estado != null && s.estado != estado) return false;
      if (tipo != null && s.tipoActividad != tipo) return false;
      if (query.isNotEmpty && !s.descripcion.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }));
    _ensureExpanded();
  }

  void _ensureExpanded() {
    if (filtradas.isEmpty) return;
    final ctNames = filtradas.map((s) => s.ctname).toSet();
    if (expandedCt.value == null || !ctNames.contains(expandedCt.value)) {
      expandedCt.value = ctNames.first;
    }
  }

  void goToDetalle(SegmentoEntity segmento) {
    Get.toNamed(AppRoutes.detalle, arguments: segmento);
  }
}
