import '../entities/user_entity.dart';

abstract class AuthRepository {
  Future<UserModel> login(String usuario, String password);
  Future<void> logout();
  Future<UserModel?> getCurrentUser();
  Future<bool> isAuthenticated();
}
