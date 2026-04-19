import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_router.dart';
import '../../data/repository/auth_repository_impl.dart';

class LoginPageController extends GetxController {
  final _repo = AuthRepositoryImpl();

  final usuarioController = TextEditingController();
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final isLoading = false.obs;
  final showPassword = false.obs;
  final error = Rx<String?>(null);

  @override
  void onInit() {
    super.onInit();
    _loadLastUsuario();
  }

  Future<void> _loadLastUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString('last_usuario');
    if (last != null) {
      usuarioController.text = last;
    }
  }

  void toggleShowPassword() => showPassword.value = !showPassword.value;

  Future<void> login() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    isLoading.value = true;
    error.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_usuario', usuarioController.text.trim());
      await _repo.login(
        usuarioController.text.trim(),
        passwordController.text,
      );
      Get.offAllNamed(AppRoutes.actividades);
    } catch (e) {
      error.value = _parseError(e);
    } finally {
      isLoading.value = false;
    }
  }

  String _parseError(Object e) {
    final str = e.toString();
    if (str.contains('401') || str.contains('credencial')) {
      return 'Usuario o contraseña incorrectos';
    }
    if (str.contains('SocketException') || str.contains('network')) {
      return 'Sin conexión a internet';
    }
    return 'Error al iniciar sesión. Inténtalo de nuevo.';
  }

  @override
  void onClose() {
    usuarioController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
