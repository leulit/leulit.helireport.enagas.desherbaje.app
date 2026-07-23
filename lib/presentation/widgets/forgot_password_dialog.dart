import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_theme.dart';

/// Pide el email para recuperar la contraseña. Devuelve el email (trim) o
/// `null` si el usuario cancela.
Future<String?> showForgotPasswordDialog() =>
    Get.dialog<String>(const _ForgotPasswordDialog());

/// StatefulWidget para que el `TextEditingController` lo libere el framework
/// cuando la ruta ya no existe: liberarlo al resolver el future de
/// `Get.dialog` es demasiado pronto (el diálogo sigue animando la salida y su
/// `TextField` se reconstruye) → "TextEditingController used after dispose".
class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog();

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Get.back<String>(result: _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recuperar contraseña'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Introduce tu email y te enviaremos las instrucciones para '
              'recuperar tu contraseña.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Introduce tu email' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back<String>(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.moduleGreen,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
