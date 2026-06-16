import 'package:get/get.dart';

import '../../core/app_di.dart';
import '../../core/app_log.dart';
import '../../core/app_router.dart';

class SplashController extends GetxController {
  final isLoading = true.obs;
  final error = Rxn<String>();

  @override
  void onInit() {
    super.onInit();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    isLoading.value = true;
    error.value = null;
    try {
      await AppDI.init();
      Get.offAllNamed(AppRoutes.login);
    } catch (e, s) {
      AppLog.e('Error en inicialización de AppDI', error: e, stackTrace: s);
      error.value = e.toString();
      isLoading.value = false;
    }
  }

  /// Reinicia el completer y vuelve a intentar el bootstrap.
  /// Debe llamar [AppDI.resetForTest] primero para que [AppDI.init]
  /// vuelva a ejecutar [_init] desde cero.
  void retry() {
    AppDI.resetForTest();
    _bootstrap();
  }
}
