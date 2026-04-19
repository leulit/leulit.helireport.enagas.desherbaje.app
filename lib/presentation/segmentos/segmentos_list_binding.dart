import 'package:get/get.dart';

import 'segmentos_list_controller.dart';


class SegmentosListBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SegmentosListController>(
        () => SegmentosListController());
  }
}
