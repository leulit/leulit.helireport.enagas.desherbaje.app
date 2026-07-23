import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_theme.dart';
import '../../data/network/network_error.dart';

/// Pide el email para recuperar la contraseña y dispara el envío del código
/// llamando a [onSubmit]. El diálogo NO se cierra ante un error: muestra el
/// motivo inline y deja al operador corregir el email sin reabrirlo. Solo
/// resuelve con el email (trim) cuando [onSubmit] tiene éxito, o con `null`
/// si el usuario cancela.
///
/// [onSubmit] recibe el email y lanza si el backend/red rechaza (el diálogo
/// traduce la excepción a un mensaje legible).
Future<String?> showForgotPasswordDialog({
  required Future<void> Function(String email) onSubmit,
}) =>
    Get.dialog<String>(_ForgotPasswordDialog(onSubmit: onSubmit));

/// StatefulWidget para que el `TextEditingController` lo libere el framework
/// cuando la ruta ya no existe: liberarlo al resolver el future de
/// `Get.dialog` es demasiado pronto (el diálogo sigue animando la salida y su
/// `TextField` se reconstruye) → "TextEditingController used after dispose".
class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.onSubmit});

  final Future<void> Function(String email) onSubmit;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final email = _controller.text.trim();
    setState(() {
      _isSending = true;
      _error = null;
    });
    try {
      await widget.onSubmit(email);
      if (!mounted) return;
      Get.back<String>(result: email);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _parseError(e));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _parseError(Object e) {
    if (e is NetworkError) {
      switch (e.category) {
        case NetworkErrorCategory.offline:
          return 'Se requiere conexión a internet para recuperar la contraseña';
        case NetworkErrorCategory.timeout:
          return 'La conexión tardó demasiado. Inténtalo de nuevo.';
        case NetworkErrorCategory.unauthorized:
        case NetworkErrorCategory.conflict:
        case NetworkErrorCategory.retryable:
        case NetworkErrorCategory.unrecoverable:
          return 'Error del servidor. Inténtalo de nuevo.';
      }
    }
    // El provider lanza Exception(mensaje del backend): email inexistente,
    // envío fallido… Se muestra tal cual.
    return e.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Diálogo lo más ancho posible: margen mínimo a los lados de la pantalla.
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      title: const Text('Recuperar contraseña'),
      content: SizedBox(
        // Fuerza el ancho al máximo disponible dentro del insetPadding.
        width: MediaQuery.of(context).size.width,
        child: Form(
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
                enabled: !_isSending,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Email',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Introduce tu email'
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Get.back<String>(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.moduleGreen,
            foregroundColor: Colors.white,
          ),
          onPressed: _isSending ? null : _submit,
          child: _isSending
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Enviar'),
        ),
      ],
    );
  }
}
