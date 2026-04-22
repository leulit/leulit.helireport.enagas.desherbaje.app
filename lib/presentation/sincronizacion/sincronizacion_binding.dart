import 'package:get/get.dart';
import 'sincronizacion_controller.dart';

class SincronizacionBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SincronizacionController>(() => SincronizacionController());
  }
}
