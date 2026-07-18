import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/repository/auth_repository_impl.dart';
import '../app_di.dart';
import '../app_router.dart';
import '../sync/sync.dart';

/// Listens to [SyncActions.authExpired] and reacts globally:
/// 1. Clears the persisted auth session (token + prefs).
/// 2. Navigates to the login screen, removing the back stack.
/// 3. Notifies the user that their session expired.
///
/// **Hoy este handler es inalcanzable**: nada en `lib/` lanza ya
/// [AuthExpiredException] (solo lo hacen los tests del motor de sync). Sigue
/// registrado al arranque, pero no se dispara nunca.
///
/// **No lo recableéis a un 401.** Esta API no tiene sesión ni Bearer: la firma
/// HMAC es la única autenticación (§1 del contrato), así que un 401 es SIEMPRE
/// un fallo de firma (secreto erróneo, reloj desfasado >5 min, path mal
/// firmado) y JAMÁS caducidad de sesión. Enganchar esto a un 401 desloguearía
/// al operador en campo por un desfase de reloj, que es justo lo que el
/// contrato prohíbe: los 401 se mapean a `SyncUnrecoverable` en
/// `syncOutcomeFromNetworkError`. Cualquier uso futuro de esta máquina exige un
/// disparador que sea de verdad expiración de sesión.
class AuthExpirationHandler extends GetxService {
  String? _handlerId;
  bool _handling = false;

  @override
  void onInit() {
    super.onInit();
    _handlerId = SyncActions.authExpired.on(
      (_) => _onAuthExpired(),
      debugLabel: 'AuthExpirationHandler.authExpired',
    );
  }

  @override
  void onClose() {
    final id = _handlerId;
    if (id != null) {
      SyncActions.authExpired.off(id);
      _handlerId = null;
    }
    super.onClose();
  }

  Future<void> _onAuthExpired() async {
    // The drain emits one authExpired per affected job in pathological
    // cases; a re-entrancy guard keeps the navigation/snackbar single-shot
    // until the user re-logs in.
    if (_handling) return;
    _handling = true;
    try {
      await AuthRepositoryImpl().logout();
      AppDI.sessionState.set(false);
      if (Get.currentRoute != AppRoutes.login) {
        Get.offAllNamed(AppRoutes.login);
      }
      Get.snackbar(
        'Sesión caducada',
        'Tu sesión ha expirado. Por favor, vuelve a iniciar sesión.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange.shade700,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
      );
    } finally {
      _handling = false;
    }
  }
}
