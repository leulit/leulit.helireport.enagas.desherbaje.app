import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_theme.dart';

/// Non-dismissible dialog that asks for the final name of a traza. Shared by
/// [TrackRecordButton] (finishing the recording currently in progress) and
/// the post-login recovery flow (naming a traza left open by a crash,
/// triggered from a controller with no `BuildContext` of its own).
///
/// Uses `Get.dialog` (not `showDialog(context: ...)`) precisely so it can be
/// invoked from either place without threading a `BuildContext` through.
///
/// - No Cancel action, `barrierDismissible: false`, and the Android back
///   gesture is blocked ([PopScope.canPop] = false): the only way out is
///   "Aceptar".
/// - Empty/whitespace-only input keeps [initialName].
/// - Always resolves to a non-empty name — never `null`.
Future<String> showFinalizeTrazaDialog({required String initialName}) async {
  final controller = TextEditingController(text: initialName);
  try {
    final result = await Get.dialog<String>(
      PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Finalizar registro de traza'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Nombre de la traza',
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.moduleGreen,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final raw = controller.text.trim();
                Get.back<String>(result: raw.isEmpty ? initialName : raw);
              },
              child: const Text('Aceptar'),
            ),
          ],
        ),
      ),
      barrierDismissible: false,
    );
    return result ?? initialName;
  } finally {
    controller.dispose();
  }
}
