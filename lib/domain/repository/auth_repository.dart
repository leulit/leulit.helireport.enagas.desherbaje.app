import '../entities/user_entity.dart';

abstract class AuthRepository {
  Future<UserEntity> login(String usuario, String password);
  Future<void> logout();
  Future<UserEntity?> getCurrentUser();
  Future<bool> isAuthenticated();
}
