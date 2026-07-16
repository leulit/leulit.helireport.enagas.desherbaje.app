import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Shared helpers for remote adapters and fetchers.
///
/// Lives in `data/sync` (not `core/sync`) because it depends on
/// [FlutterSecureStorage] and on Enagas-specific response shapes — keeping
/// the generic motor in `core/sync` free from those dependencies.

/// Reads the bearer token stored under [key] and returns the Authorization
/// header map, or `null` when no token is stored.
Future<Map<String, String>?> bearerAuthHeader(
  FlutterSecureStorage storage, {
  String key = 'auth_token',
}) async {
  final token = await storage.read(key: key);
  if (token == null) return null;
  return {'Authorization': 'Bearer $token'};
}

/// Scans [payload] for the first key in [keys] whose value is numeric
/// (int, num, or a parseable String) and returns it as an [int].
///
/// Key priority: `'id'` → `'remote_id'` → `'remoteId'` → `'itemId'`.
/// Returns `null` when none of the keys are present or parseable.
int? extractRemoteIntId(
  Map<dynamic, dynamic> payload, {
  List<String> keys = const ['id', 'remote_id', 'remoteId', 'itemId'],
}) {
  for (final key in keys) {
    final value = payload[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

/// Parses [remoteId] as an integer.
///
/// Returns `null` when [remoteId] is `null` or not a valid integer string.
int? parseRemoteId(String? remoteId) =>
    remoteId == null ? null : int.tryParse(remoteId);

/// Convención backend: HTTP 200 + body que señala error de negocio
/// (`{ok:false}` / `{success:false}` / `error`|`error_message` no vacío).
/// Se usa ADEMÁS del status HTTP, nunca en su lugar.
bool bodyIndicatesError(dynamic data) {
  if (data is! Map) return false;
  final m = data is Map<String, dynamic> ? data : data.cast<String, dynamic>();
  if (m['ok'] == false || m['success'] == false) return true;
  final err = m['error'] ?? m['error_message'] ?? m['errorMessage'];
  if (err is String) return err.isNotEmpty;
  if (err is Map) return err.isNotEmpty;
  if (err is List) return err.isNotEmpty;
  return false;
}

/// Mensaje legible del body de error, si lo hay.
String? bodyErrorMessage(dynamic data) {
  if (data is! Map) return null;
  final m = data is Map<String, dynamic> ? data : data.cast<String, dynamic>();
  final err = m['error'] ?? m['error_message'] ?? m['errorMessage'];
  if (err is String && err.isNotEmpty) return err;
  if (err is Map && err['message'] is String) return err['message'] as String;
  return null;
}
