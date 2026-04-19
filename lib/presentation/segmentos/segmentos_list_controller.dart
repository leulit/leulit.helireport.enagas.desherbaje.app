import 'package:get/get.dart';
import '../../core/result/data_result.dart';
import '../../data/repository/actividad_repository_impl.dart';
import '../../domain/entities/actividad_entity.dart';
import '../../domain/usecases/get_actividades_usecase.dart';

class SegmentosListController extends GetxController {
  late final GetSegmentosUseCase _useCase;

  final actividades = <ActividadEntity>[].obs;
  final filtradas = <ActividadEntity>[].obs;
  final isLoading = false.obs;
  final error = Rx<String?>(null);
  final selectedEstado = Rx<EstadoActividad?>(null);
  final selectedTipo = Rx<TipoActividad?>(null);
  final filterDescripcion = ''.obs;

  @override
  void onInit() {
    super.onInit();
    _useCase = GetSegmentosUseCase(ActividadRepositoryImpl());
    debounce(
      filterDescripcion,
      (_) => _applyFilter(),
      time: const Duration(milliseconds: 300),
    );
    loadActividades();
  }

  Future<void> loadActividades() async {
    isLoading.value = true;
    error.value = null;
    final result = await _useCase.execute();
    switch (result) {
      case DataSuccess(:final data):
        actividades.assignAll(data);
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

  void _applyFilter() {
    final query = filterDescripcion.value.trim().toLowerCase();
    final estado = selectedEstado.value;
    final tipo = selectedTipo.value;

    filtradas.assignAll(actividades.where((a) {
      if (estado != null && a.estado != estado) {
        return false;
      }
      if (tipo != null && !a.segmentos.any((s) => s.tipoActividad == tipo)) {
        return false;
      }
      if (query.isNotEmpty && !a.descripcion.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }));
  }

  void goToDetalle(ActividadEntity actividad) {
    Get.toNamed('/actividades/detalle', arguments: actividad);
  }
}
