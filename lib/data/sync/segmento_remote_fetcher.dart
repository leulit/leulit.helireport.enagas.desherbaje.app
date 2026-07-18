import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_endpoints.dart';
import '../../core/app_log.dart';
import '../../core/sync/contracts/remote_fetcher.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../network/network_error.dart';
import '../network/network_service.dart';

/// [RemoteFetcher] for [SegmentoEntity]. Pulls the contractor download set
/// (segmentos en estado `propuesta` + `validada`) for the authenticated
/// operator's CTs, enriched with `imagenes[]`/`mensajes[]` (vídeos incluidos
/// como filas de `imagenes[]` con `mime_type` `video/*`). La identidad de cada
/// hijo es su `id` entero (§8): `client_id` NO existe en esta API, así que no
/// hay dedup local↔nube por ese campo.
///
/// The endpoint `GET /segmentos/contratista?cts=…` keys on CT **names**
/// (`ct-burgos,ct-plasencia,…`), URL-encoded and comma-separated in the
/// querystring — NOT on ctids. Names are read from the persisted user
/// (`user_json`, field `UserCt.ct`). The flat `user_cts` list holds ctids and
/// is reserved for the local read/grouping path; it must not be sent here.
/// La firma HMAC del interceptor incluye el querystring (§9 del contrato).
///
/// If no CTs are available, returns an empty list (caller will see "nothing
/// to import").
class SegmentoRemoteFetcher implements RemoteFetcher<SegmentoEntity> {
  static const _userJsonKey = 'user_json';

  final NetworkService _network;

  SegmentoRemoteFetcher(this._network);

  @override
  Future<List<SegmentoEntity>> pullAll() async {
    final names = await _readCtNames();
    if (names.isEmpty) return const [];

    // El backend separa por coma; cada nombre se URL-encodea por si trae
    // espacios o caracteres reservados, pero las comas se dejan literales.
    final cts = names.map(Uri.encodeComponent).join(',');

    try {
      // Sin cabecera de Bearer: esta API no tiene token de sesión, el HMAC del
      // interceptor es la única autenticación (§1).
      final response = await _network.get(
        ApiEndpoints.segmentosContratista(cts),
      );
      final raw = response.data as List? ?? const [];
      final remote = raw
          .whereType<Map>()
          .map((m) => SegmentoEntity.fromJson(m.cast<String, dynamic>()))
          .toList();
      return remote;
    } on NetworkError catch (err) {
      // 401/403 = firma HMAC rechazada, nunca sesión caducada (§1 del
      // contrato). Se relanza para que el pull acabe en PullOutcome.error;
      // deslogar al operador por un desfase de reloj sería destructivo.
      if (err.category == NetworkErrorCategory.unauthorized) {
        AppLog.e(
          'HMAC signature rejected (HTTP ${err.statusCode}) on '
          'GET /segmentos/contratista — check HMAC_SECRET and device clock '
          '(signature window is ±5 min): ${err.message}',
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
