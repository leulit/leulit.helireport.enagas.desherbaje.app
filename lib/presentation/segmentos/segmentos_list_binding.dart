import 'package:get/get.dart';
import '../../data/repository/segmento_repository_impl.dart';
import '../../domain/repository/segmento_repository.dart';
import '../../domain/usecases/get_segmentos_usecase.dart';
import 'segmentos_list_controller.dart';

class SegmentosListBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SegmentoRepository>(() => SegmentoRepositoryImpl());
    Get.lazyPut<GetSegmentosUseCase>(
      () => GetSegmentosUseCase(Get.find<SegmentoRepository>()),
    );
    Get.lazyPut<SegmentosListController>(
      () => SegmentosListController(Get.find<GetSegmentosUseCase>()),
    );
  }
}
