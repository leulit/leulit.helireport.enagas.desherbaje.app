import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';

import '../../../core/app_di.dart';

class GasoductosMapLayer extends StatelessWidget {
  const GasoductosMapLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AppDI.gasoductosService;
    return Obx(() => PolylineLayer(polylines: service.polylines.toList()));
  }
}
