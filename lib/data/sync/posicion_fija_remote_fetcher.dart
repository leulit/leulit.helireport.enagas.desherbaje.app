import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_endpoints.dart';
import '../../core/app_log.dart';
import '../../core/sync/contracts/remote_fetcher.dart';
import '../../domain/entities/posicion_fija_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../network/network_error.dart';
import '../network/network_service.dart';

/// [RemoteFetcher] for [PosicionFijaEntity]. Pulls the full set of posiciones
/// fijas assigned to the authenticated operator's CTs from the backend.
///
/// The endpoint `GET /incidencias/posicionesfijasbycts/{cts}` keys on CT
/// **names** (`ct-burgos,ct-plasencia,…`), URL-encoded and comma-separated —
/// same convention as [SegmentoRemoteFetcher]. Names are read from the
/// persisted user (`user_json`, field `UserCt.ct`).
///
/// If no CTs are available, returns an empty list (caller will see "nothing
/// to import").
class PosicionFijaRemoteFetcher implements RemoteFetcher<PosicionFijaEntity> {
  static const _userJsonKey = 'user_json';

  final NetworkService _network;

  PosicionFijaRemoteFetcher(this._network);

  @override
  Future<List<PosicionFijaEntity>> pullAll() async {
    final names = await _readCtNames();
    if (names.isEmpty) return const [];

    // El backend separa por coma; cada nombre se URL-encodea por si trae
    // espacios o caracteres reservados, pero las comas se dejan literales.
    final cts = names.map(Uri.encodeComponent).join(',');

    try {
      // Sin cabecera de Bearer: esta API no tiene token de sesión, el HMAC del
      // interceptor es la única autenticación (§1).
      final response = await _network.get(
        ApiEndpoints.posicionesFijasByCts(cts),
      );
      final raw = response.data as List? ?? const [];
      return raw
          .whereType<Map>()
          .map((m) => PosicionFijaEntity.fromJson(m.cast<String, dynamic>()))
          .toList();
    } on NetworkError catch (err) {
      // 401/403 = firma HMAC rechazada, nunca sesión caducada (§1 del
      // contrato). Se relanza para que el pull acabe en PullOutcome.error;
      // deslogar al operador por un desfase de reloj sería destructivo.
      if (err.category == NetworkErrorCategory.unauthorized) {
        AppLog.e(
          'HMAC signature rejected (HTTP ${err.statusCode}) on '
          'GET /incidencias/posicionesfijasbycts — check HMAC_SECRET and '
          'device clock (signature window is ±5 min): ${err.message}',
        );
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
