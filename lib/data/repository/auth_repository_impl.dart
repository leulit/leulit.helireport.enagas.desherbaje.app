import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repository/auth_repository.dart';
import '../providers/auth_data_provider.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthDataProvider _provider = AuthDataProvider();
  final _storage = const FlutterSecureStorage();

  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'user_id';
  static const _userNameKey = 'user_name';
  static const _userUsuarioKey = 'user_usuario';
  static const _userJsonKey = 'user_json';
  // Lista plana de ctids; se mantiene para acceso rápido desde los use cases
  // (no requiere parsear el JSON completo del usuario).
  static const _userCtsKey = 'user_cts';

  @override
  Future<UserModel> login(String usuario, String password) async {
    final user = await _provider.login(usuario, password);
    // El endpoint de login no incluye los CTs: los pedimos por separado y
    // los inyectamos en el modelo antes de persistir.
    user.cts = await _provider.getCts(user.id);

    await _storage.write(key: _tokenKey, value: user.token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userIdKey, user.id);
    await prefs.setString(_userNameKey, user.nombre);
    await prefs.setString(_userUsuarioKey, user.usuario);
    await prefs.setString(_userJsonKey, jsonEncode(user.toJson()));
    // SharedPreferences no soporta List<int> nativamente; se serializa como
    // JSON (`[12,15,23]`) para conservar el tipo entero al leer.
    await prefs.setString(_userCtsKey, jsonEncode(user.ctsId()));
    return user;
  }

  @override
  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_userUsuarioKey);
    await prefs.remove(_userJsonKey);
    await prefs.remove(_userCtsKey);
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userJsonKey);
    if (userJson == null) return null;

    try {
      final decoded = jsonDecode(userJson) as Map<String, dynamic>;
      final user = UserModel.fromJson(decoded);
      user.token = token;
      return user;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> isAuthenticated() async {
    final token = await _storage.read(key: _tokenKey);
    return token != null && token.isNotEmpty;
  }
}
