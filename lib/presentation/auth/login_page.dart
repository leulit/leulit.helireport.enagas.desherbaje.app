import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'login_page_controller.dart';

class LoginPage extends GetView<LoginPageController> {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      body: SafeArea(
        child: Stack(
          children: [
            _LoginBody(controller: controller),
            Obx(() => controller.isSyncing.value
                ? const _SyncingOverlay()
                : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

class _LoginBody extends StatelessWidget {
  final LoginPageController controller;
  const _LoginBody({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Form(
          key: controller.formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo placeholder
              Container(
                height: 80,
                width: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF388E3C),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.eco, size: 48, color: Colors.white),
              ),
              const SizedBox(height: 32),
              const Text(
                'Helireport Desherbaje',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B5E20),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Operadores de campo',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Obx(() {
                final last = controller.lastSyncAt.value;
                return Text(
                  last == null
                      ? 'Sin datos sincronizados'
                      : 'Datos sincronizados: '
                          '${DateFormat('dd/MM/yyyy HH:mm').format(last)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: last == null
                        ? Colors.orange.shade800
                        : Colors.grey.shade600,
                  ),
                );
              }),
              const SizedBox(height: 40),
              TextFormField(
                controller: controller.usuarioController,
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Introduce tu usuario'
                    : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              Obx(() => TextFormField(
                    controller: controller.passwordController,
                    obscureText: !controller.showPassword.value,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(controller.showPassword.value
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: controller.toggleShowPassword,
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Introduce tu contraseña'
                        : null,
                    onFieldSubmitted: (_) => controller.login(),
                  )),
              const SizedBox(height: 16),
              Obx(() => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recordar contraseña',
                        style:
                            TextStyle(fontSize: 14, color: Color(0xFF1B5E20)),
                      ),
                      Switch(
                        value: controller.rememberPassword.value,
                        onChanged: (_) => controller.toggleRememberPassword(),
                        activeThumbColor: const Color(0xFF388E3C),
                      ),
                    ],
                  )),
              const SizedBox(height: 16),
              Obx(() {
                final busy =
                    controller.isLoading.value || controller.isSyncing.value;
                return Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: busy ? null : controller.login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF388E3C),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: controller.isLoading.value
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Iniciar sesión',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: busy ? null : controller.sincronizar,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: Color(0xFF388E3C), width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: controller.isSyncing.value
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF388E3C),
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Sincronizar',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF388E3C),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
              Obx(() {
                if (controller.isLoading.value) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(
                      color: Color(0xFF388E3C),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }),
              Obx(() {
                final busy =
                    controller.isLoading.value || controller.isSyncing.value;
                return Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: busy ? null : controller.forgotPassword,
                    child: const Text(
                      '¿Contraseña olvidada?',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF388E3C),
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFF388E3C),
                      ),
                    ),
                  ),
                );
              }),
              Obx(() {
                final err = controller.error.value;
                if (err == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    err,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncingOverlay extends StatelessWidget {
  const _SyncingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 4,
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Preparando sincronización…',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
