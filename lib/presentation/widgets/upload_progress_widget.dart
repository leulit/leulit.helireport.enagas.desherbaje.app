import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../fotos/captura_fotos_controller.dart';

class UploadProgressWidget extends GetWidget<CapturaFotosController> {
  const UploadProgressWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.isUploading.value) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: controller.uploadTotal.value > 0
                  ? controller.uploadCurrent.value /
                      controller.uploadTotal.value
                  : null,
              color: const Color(0xFF388E3C),
            ),
            const SizedBox(height: 4),
            Text(
              'Subiendo ${controller.uploadCurrent.value}/${controller.uploadTotal.value}...',
            ),
          ],
        ),
      );
    });
  }
}
