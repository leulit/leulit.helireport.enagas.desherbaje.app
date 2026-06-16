import 'package:get/get.dart';

import 'splash_controller.dart';

class SplashBinding extends Bindings {
  @override
  void dependencies() {
    // eager: onInit corre inmediatamente al entrar a la ruta splash
    Get.put<SplashController>(SplashController());
  }
}
