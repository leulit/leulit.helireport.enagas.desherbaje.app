
import '../../core/api_endpoints.dart';
import '../../core/app_di.dart';
import '../../data/network/network_service.dart';
import '../../domain/entities/user_entity.dart';

class AuthDataProvider {
  final NetworkService _network = AppDI.networkService;

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
