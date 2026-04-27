import 'package:get/get.dart';
import 'package:helireport_desherbaje/core/app_di.dart';
import 'package:helireport_desherbaje/core/app_router.dart';

class InitializerController extends GetxController {
  @override
  void onInit() {
    super.onInit();
    _startServices();
  }

  void _startServices() async {
    try {
      await AppDI.init();
      Get.offAllNamed(AppRoutes.login); // Salta al login cuando termine
    } catch (e) {
      print("Error en inicialización: $e");
    }
  }
}