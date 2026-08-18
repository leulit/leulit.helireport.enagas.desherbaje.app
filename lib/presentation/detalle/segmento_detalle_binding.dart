import 'package:get/get.dart';

import '../../core/screen_controller.dart';
import 'media_gis_layer.dart';
import 'segmento_detalle_controller.dart';

class SegmentoDetalleBinding extends Bindings {
  @override
  void dependencies() {
    putScreenController<SegmentoDetalleController>(() => SegmentoDetalleController());
    putScreenController<MediaGisLayerController>(() => MediaGisLayerController());
  }
}
