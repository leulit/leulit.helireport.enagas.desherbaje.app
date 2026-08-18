import 'package:get/get.dart';

import '../../core/screen_controller.dart';
import 'sincronizacion_controller.dart';

class SincronizacionBinding extends Bindings {
  @override
  void dependencies() {
    putScreenController<SincronizacionController>(() => SincronizacionController());
  }
}
