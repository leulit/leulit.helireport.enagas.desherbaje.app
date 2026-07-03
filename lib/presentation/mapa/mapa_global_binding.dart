import 'package:get/get.dart';

import 'layers/posiciones_fijas_map_controller.dart';
import 'layers/segmentos_map_controller.dart';
import 'mapa_global_controller.dart';

class MapaGlobalBinding extends Bindings {
  @override
  void dependencies() {
    // SegmentosMapController y PosicionesFijasMapController primero:
    // MapaGlobalController.onInit los accede vía Get.find<...>() al llamar
    // loadAll().
    Get.lazyPut<SegmentosMapController>(() => SegmentosMapController());
    Get.lazyPut<PosicionesFijasMapController>(
        () => PosicionesFijasMapController());
    Get.lazyPut<MapaGlobalController>(() => MapaGlobalController());
  }
}
