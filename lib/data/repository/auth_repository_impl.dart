import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/ct_info_entity.dart';
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
  static const _userCtsKey = 'user_cts';
  static const _userCtInfosKey = 'user_ct_infos';

  @override
  Future<UserEntity> login(String usuario, String password) async {
    final user = await _provider.login(usuario, password);
    await _storage.write(key: _tokenKey, value: user.token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userIdKey, user.id);
    await prefs.setString(_userNameKey, user.nombre);
    await prefs.setString(_userUsuarioKey, user.usuario);
    await prefs.setStringList(_userCtsKey, user.cts);
    await prefs.setString(
      _userCtInfosKey,
      jsonEncode(
        user.ctInfos
            .map((c) => {'ct': c.ct, 'nombre': c.nombre, 'filename': c.filename})
            .toList(),
      ),
    );
    return user;
  }

  @override
  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_userUsuarioKey);
    await prefs.remove(_userCtsKey);
    await prefs.remove(_userCtInfosKey);
  }

  @override
  Future<UserEntity?> getCurrentUser() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_userIdKey);
    if (id == null) return null;

    final ctsList = prefs.getStringList(_userCtsKey) ?? [];
    final ctInfosJson = prefs.getString(_userCtInfosKey);
    List<CtInfo> ctInfos;
    if (ctInfosJson != null) {
      try {
        final decoded = jsonDecode(ctInfosJson) as List;
        ctInfos = decoded
            .map((e) => CtInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        ctInfos = ctsList.map(CtInfo.fromString).toList();
      }
    } else {
      ctInfos = ctsList.map(CtInfo.fromString).toList();
    }

    return UserEntity(
      id: id,
      usuario: prefs.getString(_userUsuarioKey) ?? '',
      nombre: prefs.getString(_userNameKey) ?? '',
      cts: ctsList,
      ctInfos: ctInfos,
      token: token,
    );
  }

  @override
  Future<bool> isAuthenticated() async {
    final token = await _storage.read(key: _tokenKey);
    return token != null && token.isNotEmpty;
  }
}
