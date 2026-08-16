// Tests de idempotencia de AppDI.init().
//
// La propiedad que se verifica: el campo _initFuture usa el patrón ??= que
// garantiza que llamadas concurrentes o secuenciales a init() devuelven el
// mismo objeto Future — sin importar cuántas veces se llame.
//
// Los servicios internos de AppDI usan platform channels que no están
// disponibles fuera de un emulador. Para aislar la propiedad de idempotencia
// (puramente sincrónica — se puede observar antes de que el Future resuelva)
// los tests NO awaitan el Future y usan runZonedGuarded para absorber los
// MissingPluginException que inevitablemente lanza el código async en background.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:helireport_desherbaje/core/app_di.dart';

/// Ejecuta [body] dentro de una zona que silencia todos los errores,
/// devolviendo el resultado síncrono de [body] sin awaitar nada.
T _guarded<T>(T Function() body) {
  late T result;
  runZonedGuarded(() {
    result = body();
  }, (_, _) {
    // absorber MissingPluginException y similares
  });
  return result;
}

void main() {
  setUp(() {
    Get.reset();
    AppDI.resetForTest();
  });

  tearDown(() {
    Get.reset();
    AppDI.resetForTest();
  });

  // ── (a) misma instancia de Future ─────────────────────────────────────

  test(
    'dos llamadas consecutivas a init() devuelven el mismo Future (??= idiom)',
    () {
      late Future<void> f1, f2;
      _guarded(() {
        f1 = AppDI.init();
        f2 = AppDI.init();
      });

      expect(identical(f1, f2), isTrue,
          reason:
              'la segunda llamada reutiliza _initFuture, no arranca _init() de nuevo');
    },
  );

  // ── (b) concurrencia ──────────────────────────────────────────────────

  test(
    'tres llamadas paralelas comparten el mismo objeto Future',
    () {
      late Future<void> f1, f2, f3;
      _guarded(() {
        f1 = AppDI.init();
        f2 = AppDI.init();
        f3 = AppDI.init();
      });

      expect(identical(f1, f2), isTrue);
      expect(identical(f2, f3), isTrue);
    },
  );

  // ── (c) resetForTest crea un nuevo Future ─────────────────────────────

  test(
    'resetForTest() hace que la siguiente init() cree un Future distinto',
    () {
      late Future<void> f1, f2;
      _guarded(() {
        f1 = AppDI.init();
      });

      AppDI.resetForTest();
      Get.reset();

      _guarded(() {
        f2 = AppDI.init();
      });

      expect(identical(f1, f2), isFalse,
          reason: 'tras resetForTest(), init() devuelve un Future nuevo');
    },
  );

  // ── (d) n llamadas sin reset = mismo Future ───────────────────────────

  test(
    'sin resetForTest, cualquier número de llamadas devuelve siempre el mismo Future',
    () {
      late Future<void> f1, f2, f3, f4;
      _guarded(() {
        f1 = AppDI.init();
        f2 = AppDI.init();
        f3 = AppDI.init();
        f4 = AppDI.init();
      });

      expect(identical(f1, f2), isTrue);
      expect(identical(f1, f3), isTrue);
      expect(identical(f1, f4), isTrue);
    },
  );
}
