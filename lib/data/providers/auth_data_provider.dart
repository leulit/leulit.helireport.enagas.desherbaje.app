import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import '../../data/network/network_service.dart';
import '../../domain/entities/user_entity.dart';

class AuthDataProvider {
  final Dio _dio = Get.find<NetworkService>().dio;

  Future<UserEntity> login(String usuario, String password) async {
    const path = '/users/login';
    final response = await _dio.post(
      path,
      data: {'usuario': usuario, 'password': password},
    );
    final data = response.data as Map<String, dynamic>;
    final rows = data['rows'] as List?;
    if (rows == null || rows.isEmpty) {
      throw Exception('Invalid credentials');
    }
    final rowJson = rows[0] as Map<String, dynamic>;
    final token = (rowJson['token'] as String?) ?? '';
    final user = UserEntity.fromJson(rowJson, token);
    return user;
  }
}
