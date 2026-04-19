import 'package:get/get.dart';
import 'captura_fotos_controller.dart';

class CapturaFotosBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CapturaFotosController>(() => CapturaFotosController());
  }
}
