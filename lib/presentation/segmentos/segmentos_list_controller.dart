import 'package:get/get.dart';
import 'package:helireport_desherbaje/core/my_getx_controller.dart';
import '../../core/app_router.dart';
import '../../core/result/data_result.dart';
import '../../data/repository/auth_repository_impl.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/usecases/get_segmentos_usecase.dart';

class SegmentosListController extends MyGetxController {
  SegmentosListController(this._useCase);

  final GetSegmentosUseCase _useCase;
  final _authRepo = AuthRepositoryImpl();

  final segmentos = <SegmentoEntity>[].obs;
  final filtradas = <SegmentoEntity>[].obs;
  final isLoading = false.obs;
  final error = Rx<String?>(null);
  final selectedEstado = Rx<EstadoActividad?>(null);
  final selectedTipo = Rx<TipoActividad?>(null);
  final filterDescripcion = ''.obs;

  /// Usuario logueado, para poder resolver nombres de CT en la UI.
  UserModel? _user;

  /// CT cuya tarjeta de grupo está expandida en el acordeón. `null` colapsa
  /// todos. Se inicializa al primer CT con resultados al cargar.
  final expandedCtId = Rx<int?>(null);

  @override
  void myOnInit() {
    debounce(
      filterDescripcion,
      (_) => _applyFilter(),
      time: const Duration(milliseconds: 300),
    );
    _bootstrap();
  }

  /// Carga el usuario antes que los segmentos para garantizar que la primera
  /// renderización del listado ya disponga del nombre de cada CT.
  Future<void> _bootstrap() async {
    _user = await _authRepo.getCurrentUser();
    await loadSegmentos();
  }

  /// Nombre legible del CT a partir de su id. Cae a `CT $id` si el usuario
  /// no está cargado o el ct no figura en sus asignados.
  String ctNameById(int ctId) {
    final name = _user?.ctNameById(ctId);
    if (name != null && name.isNotEmpty) return name;
    return 'CT $ctId';
  }

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

  void toggleCtExpanded(int ctId) {
    expandedCtId.value = expandedCtId.value == ctId ? null : ctId;
  }

  /// Mapa CT → segmentos, para el render agrupado.
  Map<int, List<SegmentoEntity>> get groupedByCt {
    final map = <int, List<SegmentoEntity>>{};
    for (final s in filtradas) {
      map.putIfAbsent(s.ctId, () => []).add(s);
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
    final ctIds = filtradas.map((s) => s.ctId).toSet();
    if (expandedCtId.value == null || !ctIds.contains(expandedCtId.value)) {
      expandedCtId.value = ctIds.first;
    }
  }

  void goToDetalle(SegmentoEntity segmento) {
    Get.toNamed(AppRoutes.detalle, arguments: segmento);
  }
}
