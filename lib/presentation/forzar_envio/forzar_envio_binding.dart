import 'package:get/get.dart';

import '../../core/app_di.dart';
import '../../data/repository/segmento_repository_impl.dart';
import '../../domain/repository/segmento_repository.dart';
import '../../domain/usecases/get_segmentos_usecase.dart';
import 'forzar_envio_controller.dart';

class ForzarEnvioBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<SegmentoRepository>()) {
      Get.lazyPut<SegmentoRepository>(() => SegmentoRepositoryImpl());
    }
    if (!Get.isRegistered<GetSegmentosUseCase>()) {
      Get.lazyPut<GetSegmentosUseCase>(
        () => GetSegmentosUseCase(Get.find<SegmentoRepository>()),
      );
    }
    // SyncEngine y ConnectivityService son GetxServices permanentes registrados
    // en AppDI (app_di.dart). El binding solo los resuelve via Get.find.
    Get.lazyPut<ForzarEnvioController>(
      () => ForzarEnvioController(
        Get.find<GetSegmentosUseCase>(),
        AppDI.syncEngine,
        AppDI.connectivityService,
      ),
    );
  }
}
