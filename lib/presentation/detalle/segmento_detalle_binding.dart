import 'package:get/get.dart';
import 'segmento_detalle_controller.dart';

class SegmentoDetalleBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SegmentoDetalleController>(() => SegmentoDetalleController());
  }
}
