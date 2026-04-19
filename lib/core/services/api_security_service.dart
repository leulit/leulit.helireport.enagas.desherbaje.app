import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../app_config.dart';

class ApiSecurityService {
  static Map<String, String> buildHeaders(
    String method,
    String path, {
    String? token,
    bool isMultipart = false,
  }) {
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = const Uuid().v4();
    final payload = '$method$path$timestamp$nonce';
    final key = utf8.encode(AppConfig.hmacSecret);
    final bytes = utf8.encode(payload);
    final hmac = Hmac(sha256, key);
    final signature = hmac.convert(bytes).toString();

    return {
      'x-flutter-signature': signature,
      'x-flutter-timestamp': timestamp,
      'x-flutter-nonce': nonce,
      if (token != null) 'Authorization': 'Bearer $token',
      if (!isMultipart) 'Content-Type': 'application/json',
    };
  }
}
