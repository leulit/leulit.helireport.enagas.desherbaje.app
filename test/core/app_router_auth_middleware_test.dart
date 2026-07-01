import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';

import 'package:helireport_desherbaje/core/app_router.dart';
import 'package:helireport_desherbaje/core/services/session_state.dart';

void main() {
  setUp(() async {
    Get.reset();
    await DI.reset();
  });

  tearDown(() async {
    Get.reset();
    await DI.reset();
  });

  group('AuthMiddleware.redirect', () {
    test('(a) without session → redirects to /login', () {
      final session = SessionState();
      session.set(false);
      DI.registerSingleton<SessionState>(session);

      final result = AuthMiddleware().redirect(AppRoutes.segmentos);

      expect(result, isNotNull);
      expect(result!.name, equals(AppRoutes.login));
    });

    test('(b) with session → returns null (no redirect)', () {
      final session = SessionState();
      session.set(true);
      DI.registerSingleton<SessionState>(session);

      final result = AuthMiddleware().redirect(AppRoutes.segmentos);

      expect(result, isNull);
    });

    test('(c) /login route always returns null — no redirect loop', () {
      // Even without SessionState registered the login page must never redirect.
      final result = AuthMiddleware().redirect(AppRoutes.login);
      expect(result, isNull);
    });

    test('(c) /splash route always returns null — no redirect loop', () {
      final result = AuthMiddleware().redirect(AppRoutes.splash);
      expect(result, isNull);
    });

    test('(d) SessionState not registered → redirects to /login without throwing',
        () {
      // SessionState deliberately not registered in DI.
      expect(DI.isRegistered<SessionState>(), isFalse);

      RouteSettings? result;
      expect(
        () => result = AuthMiddleware().redirect(AppRoutes.segmentos),
        returnsNormally,
      );
      expect(result, isNotNull);
      expect(result!.name, equals(AppRoutes.login));
    });
  });
}
