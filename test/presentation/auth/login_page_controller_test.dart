import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:helireport_desherbaje/data/network/network_service.dart';
import 'package:helireport_desherbaje/presentation/auth/login_page_controller.dart';

class _FakeNetworkService extends NetworkService {
  @override
  void onInit() {}
}

// LoginPageController hardcodea AuthRepositoryImpl, por lo que solo podemos
// testear el estado observable y la carga de credenciales desde SharedPreferences.
// Los tests de login/sincronizar requieren refactorizar el controller para
// aceptar AuthRepository por inyección — documentado como mejora pendiente.

void main() {
  setUp(() {
    Get.reset();
    Get.put<NetworkService>(_FakeNetworkService());
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(Get.reset);

  group('toggleShowPassword', () {
    test('starts as false', () {
      final controller = LoginPageController();
      expect(controller.showPassword.value, isFalse);
    });

    test('toggles from false to true', () {
      final controller = LoginPageController();
      controller.toggleShowPassword();
      expect(controller.showPassword.value, isTrue);
    });

    test('toggles back to false on second call', () {
      final controller = LoginPageController();
      controller.toggleShowPassword();
      controller.toggleShowPassword();
      expect(controller.showPassword.value, isFalse);
    });
  });

  group('toggleRememberPassword', () {
    test('starts as false', () {
      final controller = LoginPageController();
      expect(controller.rememberPassword.value, isFalse);
    });

    test('toggles from false to true', () {
      final controller = LoginPageController();
      controller.toggleRememberPassword();
      expect(controller.rememberPassword.value, isTrue);
    });

    test('toggles back to false on second call', () {
      final controller = LoginPageController();
      controller.toggleRememberPassword();
      controller.toggleRememberPassword();
      expect(controller.rememberPassword.value, isFalse);
    });
  });

  group('initial state', () {
    test('isLoading starts false', () {
      final controller = LoginPageController();
      expect(controller.isLoading.value, isFalse);
    });

    test('isSyncing starts false', () {
      final controller = LoginPageController();
      expect(controller.isSyncing.value, isFalse);
    });

    test('error starts null', () {
      final controller = LoginPageController();
      expect(controller.error.value, isNull);
    });
  });

  group('_loadSavedCredentials (via onInit)', () {
    test('loads last_usuario into usuarioController', () async {
      SharedPreferences.setMockInitialValues({
        'last_usuario': 'operador1',
        'remember_password': false,
      });

      final controller = LoginPageController();
      Get.put(controller);
      controller.onInit();
      await Future.delayed(Duration.zero); // let async _loadSavedCredentials run

      expect(controller.usuarioController.text, equals('operador1'));
    });

    test('loads password when remember_password is true', () async {
      SharedPreferences.setMockInitialValues({
        'last_usuario': 'operador1',
        'last_password': 'secret123',
        'remember_password': true,
      });

      final controller = LoginPageController();
      Get.put(controller);
      controller.onInit();
      await Future.delayed(Duration.zero);

      expect(controller.passwordController.text, equals('secret123'));
      expect(controller.rememberPassword.value, isTrue);
    });

    test('does NOT load password when remember_password is false', () async {
      SharedPreferences.setMockInitialValues({
        'last_usuario': 'operador1',
        'last_password': 'secret123',
        'remember_password': false,
      });

      final controller = LoginPageController();
      Get.put(controller);
      controller.onInit();
      await Future.delayed(Duration.zero);

      expect(controller.passwordController.text, isEmpty);
      expect(controller.rememberPassword.value, isFalse);
    });

    test('leaves fields empty when no saved credentials', () async {
      final controller = LoginPageController();
      Get.put(controller);
      controller.onInit();
      await Future.delayed(Duration.zero);

      expect(controller.usuarioController.text, isEmpty);
      expect(controller.passwordController.text, isEmpty);
    });
  });
}
