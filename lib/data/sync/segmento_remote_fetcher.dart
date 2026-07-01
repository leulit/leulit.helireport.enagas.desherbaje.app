import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_endpoints.dart';
import '../../core/sync/contracts/auth_expired_exception.dart';
import '../../core/sync/contracts/remote_fetcher.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../network/network_error.dart';
import '../network/network_service.dart';
import 'adapter_support.dart';

/// [RemoteFetcher] for [SegmentoEntity]. Pulls the full set of segmentos
/// assigned to the authenticated operator's CTs from the backend.
///
/// The endpoint `GET /segmentos/bycts/{cts}` keys on CT **names**
/// (`ct-burgos,ct-plasencia,…`), URL-encoded and comma-separated — NOT on
/// ctids. Names are read from the persisted user (`user_json`, field
/// `UserCt.ct`). The flat `user_cts` list holds ctids and is reserved for the
/// local read/grouping path; it must not be sent to this endpoint.
///
/// If no CTs are available, returns an empty list (caller will see "nothing
/// to import").
class SegmentoRemoteFetcher implements RemoteFetcher<SegmentoEntity> {
  static const _userJsonKey = 'user_json';

  final NetworkService _network;
  final FlutterSecureStorage _storage;

  SegmentoRemoteFetcher(
    this._network, {
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<List<SegmentoEntity>> pullAll() async {
    final names = await _readCtNames();
    if (names.isEmpty) return const [];

    // El backend separa por coma; cada nombre se URL-encodea por si trae
    // espacios o caracteres reservados, pero las comas se dejan literales.
    final cts = names.map(Uri.encodeComponent).join(',');

    try {
      final response = await _network.get(
        ApiEndpoints.segmentosByCt(cts),
        headers: await bearerAuthHeader(_storage),
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

  Future<List<String>> _readCtNames() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userJsonKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return UserModel.fromJson(decoded)
            .ctsName()
            .where((n) => n.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}
