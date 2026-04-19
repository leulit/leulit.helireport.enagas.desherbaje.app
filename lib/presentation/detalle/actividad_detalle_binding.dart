import 'package:get/get.dart';
import 'actividad_detalle_controller.dart';

class ActividadDetalleBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ActividadDetalleController>(
        () => ActividadDetalleController());
  }
}
