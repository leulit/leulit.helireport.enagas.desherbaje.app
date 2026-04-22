import 'package:get/get.dart';
import 'package:helireport_desherbaje/core/my_getx_controller.dart';

import '../../core/result/data_result.dart';
import '../../data/repository/auth_repository_impl.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/usecases/get_segmentos_usecase.dart';

/// Controller de la página "Forzar envío a nube".
///
/// Expone el mismo modelo de filtros que [SegmentosListController] —texto,
/// estado y tipo— pero lista los segmentos en plano (sin agrupar por CT).
/// Los métodos [enviarCloud] y [enviarAllCloud] son stubs: su implementación
/// llegará cuando se conecte la capa de sync.
class ForzarEnvioController extends MyGetxController {
  ForzarEnvioController(this._useCase);

  final GetSegmentosUseCase _useCase;
  final _authRepo = AuthRepositoryImpl();

  final segmentos = <SegmentoEntity>[].obs;
  final filtradas = <SegmentoEntity>[].obs;
  final isLoading = false.obs;
  final error = Rx<String?>(null);

  final selectedEstado = Rx<EstadoActividad?>(null);
  final selectedTipo = Rx<TipoActividad?>(null);
  final selectedCt = Rx<int?>(null);
  final filterDescripcion = ''.obs;

  final enviandoIds = <int>{}.obs;
  final isEnviandoTodos = false.obs;

  UserModel? _user;

  @override
  void myOnInit() {
    debounce(
      filterDescripcion,
      (_) => _applyFilter(),
      time: const Duration(milliseconds: 300),
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _user = await _authRepo.getCurrentUser();
    await loadSegmentos();
  }

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
        segmentos.assignAll(
          data.where((s) => s.estado == EstadoActividad.finalizada),
        );
        _applyFilter();
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

  void filterByCt(int? ctId) {
    selectedCt.value = ctId;
    _applyFilter();
  }

  /// Lista de CTs presentes en los segmentos cargados, ordenados por nombre.
  List<int> get ctsDisponibles {
    final ids = segmentos.map((s) => s.ctId).toSet().toList();
    ids.sort((a, b) => ctNameById(a).compareTo(ctNameById(b)));
    return ids;
  }

  void _applyFilter() {
    final query = filterDescripcion.value.trim().toLowerCase();
    final estado = selectedEstado.value;
    final tipo = selectedTipo.value;
    final ct = selectedCt.value;

    filtradas.assignAll(segmentos.where((s) {
      if (estado != null && s.estado != estado) return false;
      if (tipo != null && s.tipoActividad != tipo) return false;
      if (ct != null && s.ctId != ct) return false;
      if (query.isNotEmpty && !s.descripcion.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }));
  }

  /// Fuerza el envío de un único segmento a la nube.
  /// Pendiente de implementación.
  Future<void> enviarCloud(SegmentoEntity segmento) async {
    // TODO: implementar envío forzado de [segmento] a la nube.
  }

  /// Fuerza el envío de todos los segmentos actualmente filtrados a la nube.
  /// Pendiente de implementación.
  Future<void> enviarAllCloud() async {
    // TODO: implementar envío forzado masivo (usar [filtradas]).
  }
}
