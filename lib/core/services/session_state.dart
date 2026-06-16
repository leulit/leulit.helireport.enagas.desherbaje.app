import 'package:get/get.dart';

/// In-memory flag that records whether there is an active authenticated session.
///
/// `AuthMiddleware.redirect` is synchronous, so it cannot call secure_storage
/// directly. This service is populated at startup (see [AppDI._init]) and kept
/// in sync by [LoginPageController], [AuthExpirationHandler], and
/// [SincronizacionController] (manual logout path).
class SessionState extends GetxService {
  bool _hasSession = false;

  bool get hasSession => _hasSession;

  /// Update the session flag. Call with `true` after a successful login, or
  /// `false` after any logout path.
  void set(bool value) => _hasSession = value;
}
