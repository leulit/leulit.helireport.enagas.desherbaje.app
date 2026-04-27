import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_endpoints.dart';
import '../../core/sync/contracts/auth_expired_exception.dart';
import '../../core/sync/contracts/remote_fetcher.dart';
import '../../domain/entities/segmento_entity.dart';
import '../network/network_error.dart';
import '../network/network_service.dart';

/// [RemoteFetcher] for [SegmentoEntity]. Pulls the full set of segmentos
/// assigned to the authenticated operator's CTs from the backend.
///
/// CTs are read from `SharedPreferences` (key `user_cts`) where the
/// `AuthRepository` persists them on login. If no CTs are available, returns
/// an empty list (caller will see "nothing to import").
class SegmentoRemoteFetcher implements RemoteFetcher<SegmentoEntity> {
  static const _userCtsKey = 'user_cts';

  final NetworkService _network;
  final FlutterSecureStorage _storage;

  SegmentoRemoteFetcher(
    this._network, {
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<List<SegmentoEntity>> pullAll() async {
    final cts = await _readCts();
    if (cts.isEmpty) return const [];

    try {
      final response = await _network.get(
        ApiEndpoints.segmentosByCt(cts.join(',')),
        headers: await _authHeader(),
      );
      final raw = response.data as List? ?? const [];
      return raw
          .whereType<Map>()
          .map((m) => SegmentoEntity.fromJson(m.cast<String, dynamic>()))
          .toList();
    } on NetworkError catch (err) {
      if (err.statusCode == 401) {
        throw AuthExpiredException(err.message);
      }
      rethrow;
    }
  }

  Future<List<int>> _readCts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userCtsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<num>().map((n) => n.toInt()).toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<Map<String, String>?> _authHeader() async {
    final token = await _storage.read(key: 'auth_token');
    if (token == null) return null;
    return {'Authorization': 'Bearer $token'};
  }
}
