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
  final isSyncing = false.obs;
  final showPassword = false.obs;
  final rememberPassword = false.obs;
  final error = Rx<String?>(null);

  static const _keyLastUsuario = 'last_usuario';
  static const _keyLastPassword = 'last_password';
  static const _keyRememberPassword = 'remember_password';

  @override
  void onInit() {
    super.onInit();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_keyRememberPassword) ?? false;
    rememberPassword.value = remember;

    final lastUsuario = prefs.getString(_keyLastUsuario);
    if (lastUsuario != null) usuarioController.text = lastUsuario;

    if (remember) {
      final lastPassword = prefs.getString(_keyLastPassword);
      if (lastPassword != null) passwordController.text = lastPassword;
    }
  }

  void toggleShowPassword() => showPassword.value = !showPassword.value;

  void toggleRememberPassword() =>
      rememberPassword.value = !rememberPassword.value;

  Future<void> login() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    isLoading.value = true;
    error.value = null;
    try {
      await _saveCredentials();
      await _repo.login(
        usuarioController.text.trim(),
        passwordController.text,
      );
      Get.offAllNamed(AppRoutes.segmentos);
    } catch (e) {
      error.value = _parseError(e);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> sincronizar() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    isSyncing.value = true;
    error.value = null;
    try {
      await _saveCredentials();
      await _repo.login(
        usuarioController.text.trim(),
        passwordController.text,
      );
      Get.offAllNamed(AppRoutes.sincronizacion);
    } catch (e) {
      error.value = _parseError(e);
    } finally {
      isSyncing.value = false;
    }
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastUsuario, usuarioController.text.trim());
    await prefs.setBool(_keyRememberPassword, rememberPassword.value);
    if (rememberPassword.value) {
      await prefs.setString(_keyLastPassword, passwordController.text);
    } else {
      await prefs.remove(_keyLastPassword);
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
