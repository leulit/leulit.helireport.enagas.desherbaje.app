import '../entities/user_entity.dart';

abstract class AuthRepository {
  Future<UserModel> login(String usuario, String password);
  Future<void> logout();
  Future<UserModel?> getCurrentUser();
  Future<bool> isAuthenticated();

  /// Refresca los datos del usuario actualmente autenticado descargando de
  /// nuevo la lista de CTs y volviendo a persistir el `UserModel` completo en
  /// `SharedPreferences`. Permite que el operador reciba cambios de perfil/CTs
  /// hechos en el backend sin necesidad de cerrar sesión.
  ///
  /// Lanza si no hay sesión activa o el backend devuelve error.
  Future<UserModel> refreshUserData();

  /// Solicita al backend el envío del código OTP de recuperación. Devuelve el
  /// mensaje de confirmación; lanza `Exception` con el motivo si el backend
  /// rechaza la solicitud (email inexistente, envío fallido…).
  Future<String> requestPasswordReset(String email);

  /// Cambia la contraseña con el código OTP recibido por email. Devuelve el
  /// mensaje de éxito; lanza `Exception` con el motivo si el código es
  /// inválido/caducado o la contraseña no cumple los requisitos.
  Future<String> resetPassword({
    required String email,
    required String codigo,
    required String newPassword,
  });
}
