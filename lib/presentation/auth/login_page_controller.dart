import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_di.dart';
import '../../core/app_router.dart';
import '../../data/network/network_error.dart';
import '../../data/repository/auth_repository_impl.dart';
import '../sincronizacion/sincronizacion_controller.dart';
import '../sincronizacion/sync_models.dart';

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
  final lastSyncAt = Rx<DateTime?>(null);

  static const _keyLastUsuario = 'last_usuario';
  static const _keyLastPassword = 'last_password';
  static const _keyRememberPassword = 'remember_password';

  @override
  void onInit() {
    super.onInit();
    _loadSavedCredentials();
    _loadLastSync();
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

  /// Fecha de la descarga de datos maestros más reciente (máximo entre todos
  /// los `MasterDataKind`). `null` si nunca se ha descargado nada.
  Future<void> _loadLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    DateTime? newest;
    for (final kind in MasterDataKind.values) {
      final raw = prefs.getString(
        '${SincronizacionController.lastDownloadPrefix}${kind.name}',
      );
      if (raw == null) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) continue;
      if (newest == null || parsed.isAfter(newest)) newest = parsed;
    }
    lastSyncAt.value = newest;
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
      AppDI.sessionState.set(true);
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
      AppDI.sessionState.set(true);
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
    if (e is NetworkError) {
      switch (e.category) {
        case NetworkErrorCategory.offline:
          return 'Sin conexión a internet';
        case NetworkErrorCategory.timeout:
          return 'La conexión tardó demasiado. Inténtalo de nuevo.';
        case NetworkErrorCategory.unauthorized:
          return 'Usuario o contraseña incorrectos';
        case NetworkErrorCategory.conflict:
        case NetworkErrorCategory.retryable:
        case NetworkErrorCategory.unrecoverable:
          return 'Error del servidor. Inténtalo de nuevo.';
      }
    }
    // El provider lanza Exception('Invalid credentials') cuando el backend
    // responde 200 con `rows` vacío (credenciales no válidas, sin 401).
    if (e.toString().contains('Invalid credentials')) {
      return 'Usuario o contraseña incorrectos';
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
