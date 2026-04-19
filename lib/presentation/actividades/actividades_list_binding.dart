import 'package:get/get.dart';
import 'actividades_list_controller.dart';

class ActividadesListBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ActividadesListController>(
        () => ActividadesListController());
  }
}
