import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/app_theme.dart';
import '../../data/network/network_error.dart';
import '../../data/repository/auth_repository_impl.dart';

/// Pantalla de cambio de contraseña con código OTP. Se llega tras pedir el
/// código desde el login ("¿Contraseña olvidada?"). El operador teclea el
/// código de 6 dígitos que ha recibido por email + la contraseña nueva, y el
/// backend valida y cambia en una sola llamada.
///
/// Estado local con `setState` (sin GetX/`.obs`): la pantalla se posee a sí
/// misma y no comparte estado con nadie.
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, required this.email});

  final String email;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _repo = AuthRepositoryImpl();
  final _formKey = GlobalKey<FormState>();
  final _codigoController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isSubmitting = false;
  bool _isResending = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _codigoController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final message = await _repo.resetPassword(
        email: widget.email,
        codigo: _codigoController.text.trim(),
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      // Vuelve al login y avisa. La pantalla ya no existe → snackbar global.
      Get.back();
      Get.snackbar(
        'Contraseña actualizada',
        message,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.moduleGreen,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _parseError(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _error = null;
    });
    try {
      final message = await _repo.requestPasswordReset(widget.email);
      if (!mounted) return;
      Get.snackbar(
        'Código reenviado',
        message,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _parseError(e));
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  String _parseError(Object e) {
    if (e is NetworkError) {
      switch (e.category) {
        case NetworkErrorCategory.offline:
          return 'Sin conexión a internet';
        case NetworkErrorCategory.timeout:
          return 'La conexión tardó demasiado. Inténtalo de nuevo.';
        case NetworkErrorCategory.unauthorized:
        case NetworkErrorCategory.conflict:
        case NetworkErrorCategory.retryable:
        case NetworkErrorCategory.unrecoverable:
          return 'Error del servidor. Inténtalo de nuevo.';
      }
    }
    // El provider lanza Exception(mensaje del backend): código inválido,
    // caducado, contraseña corta… Se muestra tal cual.
    return e.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isSubmitting || _isResending;
    return Scaffold(
      backgroundColor: AppColors.moduleGreenLight,
      appBar: AppBar(
        backgroundColor: AppColors.moduleGreen,
        foregroundColor: Colors.white,
        title: const Text('Recuperar contraseña'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.mark_email_read_outlined,
                      size: 56, color: AppColors.moduleGreen),
                  const SizedBox(height: 16),
                  Text(
                    'Introduce el código de 6 dígitos que hemos enviado a '
                    '${widget.email} y tu nueva contraseña.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _codigoController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    style: const TextStyle(
                        fontSize: 22,
                        letterSpacing: 8,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'Código',
                      counterText: '',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().length != 6)
                        ? 'El código tiene 6 dígitos'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_showPassword,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Nueva contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_showPassword
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'Mínimo 6 caracteres'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmController,
                    obscureText: !_showPassword,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Repetir contraseña',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (v) => (v != _passwordController.text)
                        ? 'Las contraseñas no coinciden'
                        : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: busy ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.moduleGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Cambiar contraseña',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy ? null : _resend,
                    child: _isResending
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              color: AppColors.moduleGreen,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            '¿No te ha llegado? Reenviar código',
                            style: TextStyle(color: AppColors.moduleGreen),
                          ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
