import '../../core/api_endpoints.dart';
import '../../core/app_di.dart';
import '../../data/network/network_service.dart';
import '../../domain/entities/user_entity.dart';

class AuthDataProvider {
  // Resolución perezosa: NO resolver en construcción. AppDI.init construye
  // AuthRepositoryImpl (→ AuthDataProvider) para isAuthenticated() ANTES de
  // registrar NetworkService; un campo eager lanzaría "not registered" y el
  // catch trataría al usuario como no-autenticado en cada arranque.
  NetworkService get _network => AppDI.networkService;

  Future<UserModel> login(String usuario, String password) async {
    final response = await _network.post(
      ApiEndpoints.userLogin,
      body: {'usuario': usuario, 'password': password},
    );
    final data = response.data as Map<String, dynamic>;
    final rows = data['rows'] as List?;
    if (rows == null || rows.isEmpty) {
      throw Exception('Invalid credentials');
    }
    final rowJson = rows[0] as Map<String, dynamic>;
    final user = UserModel.fromJson(rowJson);
    if (user.token.isEmpty) {
      user.token = (rowJson['token'] as String?) ?? '';
    }
    return user;
  }

  /// Solicita el email de recuperación de contraseña. El backend responde
  /// 200 con `{success, message}` incluso cuando el email no existe, así que
  /// el desenlace se lee del cuerpo, no del status. Devuelve el mensaje a
  /// mostrar; lanza `Exception(message)` si `success != true`.
  Future<String> requestPasswordReset(String email) async {
    final response = await _network.post(
      ApiEndpoints.userForgotPassword,
      body: {'email': email},
    );
    final data = response.data;
    final message = (data is Map ? data['message'] as String? : null)?.trim();
    final ok = data is Map && data['success'] == true;
    if (!ok) {
      throw Exception(
        message?.isNotEmpty == true
            ? message
            : 'No se ha podido procesar la solicitud',
      );
    }
    return message?.isNotEmpty == true
        ? message!
        : 'En breve recibirás un email con las instrucciones para recuperar '
            'tu contraseña.';
  }

  /// Carga la lista de CTs del usuario tras el login. El endpoint de login
  /// no incluye `cts` — hay que pedirlos por separado.
  Future<List<UserCt>> getCts(int iduser) async {
    final response = await _network.get(ApiEndpoints.ctsByUser(iduser));
    final data = response.data;
    if (data is Map && data['rows'] is List) {
      return (data['rows'] as List)
          .whereType<Map>()
          .map(UserCt.fromJson)
          .toList();
    }
    return const <UserCt>[];
  }
}
