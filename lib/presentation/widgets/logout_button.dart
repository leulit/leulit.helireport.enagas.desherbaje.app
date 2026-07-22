import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../core/app_typed_actions.dart';

/// Shared "cerrar sesión" AppBar action. Replaces the four duplicated
/// `_logout()` implementations across the module's pages — same confirmation
/// dialog and navigation, plus a guard: logging out while a traza is being
/// recorded would leave the recording orphaned mid-session, so it is blocked
/// with an explanatory message instead.
class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.logout, color: AppColors.moduleGreen),
      tooltip: 'Salir',
      onPressed: () => _onPressed(context),
    );
  }

  Future<void> _onPressed(BuildContext context) async {
    final recording = await AppTypedActions.isTrazaRecording();
    if (recording) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hay una traza en grabación: finalízala antes de cerrar sesión.',
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;

    Get.dialog(
      AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que quieres cerrar sesión?'),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              Get.back();
              Get.offAllNamed(AppRoutes.login);
            },
            child: const Text('Salir', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
