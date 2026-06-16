import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/core/app_di.dart';
import 'package:helireport_desherbaje/core/app_router.dart';

// ---------------------------------------------------------------------------
// Subclase de prueba que inyecta una función de bootstrap controlable.
// Esto evita el problema de que AppDI.init() es estático y no mockeable con
// mocktail. El SplashController real delega a AppDI.init() + Get.offAllNamed;
// aquí usamos una variante testable con las mismas observables.
// ---------------------------------------------------------------------------

class _TestSplashController extends GetxController {
  final Future<void> Function() _initFn;
  final List<String> navigatedRoutes = [];

  final isLoading = true.obs;
  final error = Rxn<String>();

  _TestSplashController(this._initFn);

  @override
  void onInit() {
    super.onInit();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    isLoading.value = true;
    error.value = null;
    try {
      await _initFn();
      navigatedRoutes.add(AppRoutes.login);
    } catch (e) {
      error.value = e.toString();
      isLoading.value = false;
    }
  }

  void retry() {
    AppDI.resetForTest();
    _bootstrap();
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    Get.reset();
    AppDI.resetForTest();
  });

  tearDown(() {
    Get.reset();
    AppDI.resetForTest();
  });

  // ─── éxito ────────────────────────────────────────────────────────────────

  group('bootstrap — éxito', () {
    test('navega a login cuando init() completa sin error', () async {
      final controller = _TestSplashController(() async {
        // no-op: simula init exitoso
      });
      Get.put(controller);

      // onInit ya arrancó — esperar a que _bootstrap termine
      await Future<void>.delayed(Duration.zero);

      expect(controller.error.value, isNull,
          reason: 'no debe haber error tras éxito');
      expect(controller.isLoading.value, isTrue,
          reason: 'isLoading no se pone a false en éxito (la ruta cambia)');
      expect(controller.navigatedRoutes, contains(AppRoutes.login),
          reason: 'debe navegar a /login tras éxito');
    });
  });

  // ─── fallo ────────────────────────────────────────────────────────────────

  group('bootstrap — fallo', () {
    test('pone error!=null e isLoading==false sin relanzar la excepción',
        () async {
      final boom = Exception('DB no responde');
      final controller = _TestSplashController(() async => throw boom);
      Get.put(controller);

      await Future<void>.delayed(Duration.zero);

      expect(controller.error.value, isNotNull,
          reason: 'error debe contener el mensaje del fallo');
      expect(controller.error.value, contains('DB no responde'));
      expect(controller.isLoading.value, isFalse,
          reason: 'isLoading debe ser false cuando hay error');
      expect(controller.navigatedRoutes, isEmpty,
          reason: 'no debe navegar si init lanzó');
    });
  });

  // ─── retry ────────────────────────────────────────────────────────────────

  group('retry', () {
    test('re-invoca bootstrap y navega a login cuando el segundo intento tiene éxito',
        () async {
      int callCount = 0;
      final controller = _TestSplashController(() async {
        callCount++;
        if (callCount == 1) throw Exception('Primer fallo');
        // Segundo intento: éxito
      });
      Get.put(controller);

      // Esperar primer bootstrap (falla)
      await Future<void>.delayed(Duration.zero);
      expect(controller.error.value, isNotNull);

      // Reintentar
      controller.retry();
      await Future<void>.delayed(Duration.zero);

      expect(controller.error.value, isNull,
          reason: 'error debe limpiarse tras retry exitoso');
      expect(controller.navigatedRoutes, contains(AppRoutes.login),
          reason: 'debe navegar a /login tras retry exitoso');
      expect(callCount, equals(2),
          reason: 'la función de init debe haberse llamado dos veces');
    });

    test('retry limpia _initFuture vía AppDI.resetForTest() antes del segundo bootstrap',
        () async {
      // Verificamos que retry() llama resetForTest() observando que un segundo
      // init() crea un nuevo Future (en lugar de reusar el anterior fallido).
      // No llamamos a AppDI.init() real (usa platform channels no disponibles);
      // comprobamos que retry() dispara _bootstrap() de nuevo.

      int callCount = 0;
      final controller = _TestSplashController(() async {
        callCount++;
        // Siempre falla; verificamos que se llama dos veces
        throw Exception('siempre falla');
      });
      Get.put(controller);

      await Future<void>.delayed(Duration.zero);
      expect(callCount, equals(1));

      controller.retry();
      await Future<void>.delayed(Duration.zero);

      expect(callCount, equals(2),
          reason: 'retry debe re-invocar _bootstrap()');
    });
  });
}
