import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';

import '../../../core/services/gasoductos_service.dart';

class GasoductosMapLayer extends StatelessWidget {
  const GasoductosMapLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final service = Get.find<GasoductosService>();
    return Obx(() => PolylineLayer(polylines: service.polylines.toList()));
  }
}
