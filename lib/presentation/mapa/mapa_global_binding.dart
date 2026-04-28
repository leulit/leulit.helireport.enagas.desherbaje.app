import 'package:get/get.dart';

import 'layers/segmentos_map_controller.dart';
import 'mapa_global_controller.dart';

class MapaGlobalBinding extends Bindings {
  @override
  void dependencies() {
    // SegmentosMapController primero: MapaGlobalController.onInit lo accede
    // a través de Get.find<SegmentosMapController>() al llamar loadAll().
    Get.lazyPut<SegmentosMapController>(() => SegmentosMapController());
    Get.lazyPut<MapaGlobalController>(() => MapaGlobalController());
  }
}
