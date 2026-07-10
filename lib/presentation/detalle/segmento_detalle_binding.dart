import 'package:get/get.dart';
import 'media_gis_layer.dart';
import 'segmento_detalle_controller.dart';

class SegmentoDetalleBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SegmentoDetalleController>(() => SegmentoDetalleController());
    Get.lazyPut<MediaGisLayerController>(() => MediaGisLayerController());
  }
}
