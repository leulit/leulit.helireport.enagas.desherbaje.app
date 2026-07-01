import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../app_config.dart';

class ApiSecurityService {
  /// Esquema HMAC único de toda la API `/api/enagas/v1` (REST + vídeo).
  ///
  /// Payload: `"{timestampMs}:{METHOD}:{path}"` — [timestampMs] epoch en
  /// **milisegundos**, [method] en mayúsculas, [path] relativo (sin host,
  /// incluyendo querystring si la hubiera).
  ///
  /// Headers: `X-HMAC-Signature` (hex lowercase) y `X-Timestamp` (epoch ms).
  /// Sin nonce, sin Bearer. Ventana anti-replay ±5 min en el servidor →
  /// llamar inmediatamente antes de enviar, también en cada reintento.
  static Map<String, String> buildHmacHeaders(String method, String path) {
    final tsMs = DateTime.now().millisecondsSinceEpoch.toString();
    final payload = '$tsMs:${method.toUpperCase()}:$path';
    final key = utf8.encode(AppConfig.hmacSecret);
    final msgBytes = utf8.encode(payload);
    final hmac = Hmac(sha256, key);
    final signature = hmac.convert(msgBytes).toString(); // hex lowercase

    return {
      'X-HMAC-Signature': signature,
      'X-Timestamp': tsMs,
    };
  }
}
