import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:helireport_desherbaje/core/app_router.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';
import '../../core/result/data_result.dart';
import '../../core/services/gasoductos_service.dart';
import '../../data/repository/actividad_repository_impl.dart';
import '../../domain/entities/actividad_entity.dart';
import '../../domain/usecases/update_actividad_usecase.dart';

class ActividadDetalleController extends GetxController {
  late final UpdateActividadUseCase _updateUseCase;
  late final ActividadEntity actividad;
  final isUpdating = false.obs;
  final mapController = MapController();

  @override
  void onInit() {
    super.onInit();
    actividad = Get.arguments as ActividadEntity;
    _updateUseCase = UpdateActividadUseCase(ActividadRepositoryImpl());
    // Carga trazas de gasoductos si aún no se han cargado en esta sesión
    Get.find<GasoductosService>().ensureLoaded();
  }

  Future<void> cambiarEstado(EstadoActividad nuevoEstado) async {
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Cambiar estado'),
        content: Text('¿Cambiar estado a \'${nuevoEstado.etiqueta}\'?',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    isUpdating.value = true;
    final result = await _updateUseCase.execute(actividad.id, nuevoEstado);
    isUpdating.value = false;
    switch (result) {
      case DataSuccess(:final data) when data:
        actividad.estado = nuevoEstado;
        update();
        Get.snackbar(
          'Estado actualizado',
          'La actividad ahora está en "${nuevoEstado.etiqueta}"',
          snackPosition: SnackPosition.BOTTOM,
        );
      case DataSuccess():
        Get.snackbar('Aviso', 'El servidor no confirmó el cambio',
            snackPosition: SnackPosition.BOTTOM);
      case DataFailure(:final message):
        Get.snackbar('Error', message, snackPosition: SnackPosition.BOTTOM);
    }
  }

  void irAFotosConSegmento(SegmentoEntity segmento) {
    Get.toNamed(AppRoutes.fotos, arguments: {'segmento': segmento});
  }

  @override
  void onClose() {
    mapController.dispose();
    super.onClose();
  }
}
