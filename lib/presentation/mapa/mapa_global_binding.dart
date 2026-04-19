import 'package:get/get.dart';
import 'mapa_global_controller.dart';

class MapaGlobalBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MapaGlobalController>(() => MapaGlobalController());
  }
}
