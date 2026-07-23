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
  final result = await Get.dialog<String>(
    PopScope(
      canPop: false,
      child: _FinalizeTrazaDialog(initialName: initialName),
    ),
    barrierDismissible: false,
  );
  return result ?? initialName;
}

/// StatefulWidget so the `TextEditingController` is disposed by the framework
/// when the route is actually gone. Disposing it when `Get.dialog`'s future
/// resolves is too early: the dialog is still animating out and its
/// `TextField` keeps rebuilding, which threw "A TextEditingController was
/// used after being disposed" and left a detached subtree behind.
class _FinalizeTrazaDialog extends StatefulWidget {
  const _FinalizeTrazaDialog({required this.initialName});

  final String initialName;

  @override
  State<_FinalizeTrazaDialog> createState() => _FinalizeTrazaDialogState();
}

class _FinalizeTrazaDialogState extends State<_FinalizeTrazaDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _accept() {
    final raw = _controller.text.trim();
    Get.back<String>(result: raw.isEmpty ? widget.initialName : raw);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Finalizar registro de traza'),
      content: TextField(
        controller: _controller,
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
          onPressed: _accept,
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
