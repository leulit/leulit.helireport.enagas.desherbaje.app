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

  /// Firma en query para el endpoint de media (`GET /segmentos/thumbdb/...`),
  /// el único del API que la admite. [pathOrUrl] es el pathname CON el prefijo
  /// `/api/enagas/v1` (se acepta también la URL completa: se le extrae el
  /// pathname); nunca lleva querystring.
  ///
  /// Mismo secreto y mismo payload que [buildHmacHeaders] con `GET`, pero la
  /// firma cubre **solo el pathname**: la propia `sig` viaja en la query, así
  /// que incluirla se mordería la cola. `width`/`height` van en el path, de
  /// modo que la firma queda atada al recurso concreto.
  ///
  /// Ventana del servidor: **2 horas** (no los ±5 min del esquema de
  /// cabeceras). El reproductor fija la URL una sola vez y cada seek reusa el
  /// mismo `ts`, así que una ventana corta moriría a mitad de reproducción.
  static String buildSignedMediaUrl(String pathOrUrl) {
    final uri = Uri.parse(pathOrUrl);
    final path = uri.path;
    final tsMs = DateTime.now().millisecondsSinceEpoch.toString();
    final payload = '$tsMs:GET:$path';
    final key = utf8.encode(AppConfig.hmacSecret);
    final msgBytes = utf8.encode(payload);
    final hmac = Hmac(sha256, key);
    final signature = hmac.convert(msgBytes).toString(); // hex lowercase

    final origin =
        uri.hasAuthority ? '${uri.scheme}://${uri.authority}' : AppConfig.baseUrl;
    return '$origin$path?ts=$tsMs&sig=$signature';
  }
}
