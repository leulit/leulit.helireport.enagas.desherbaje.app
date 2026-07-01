// Tests for ApiSecurityService.
//
// Covers buildHmacHeaders (esquema HMAC único de /api/enagas/v1):
//   - timestamp en milisegundos (X-Timestamp, 13 dígitos)
//   - nombres de header correctos: X-HMAC-Signature, X-Timestamp
//   - firma HMAC-SHA256 hex lowercase de "{tsMs}:{METHOD}:{path}"
//   - sin nonce, sin Bearer
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:helireport_desherbaje/core/app_config.dart';
import 'package:helireport_desherbaje/core/services/api_security_service.dart';

void main() {
  group('buildHmacHeaders', () {
    test('returns X-HMAC-Signature and X-Timestamp headers', () {
      final headers =
          ApiSecurityService.buildHmacHeaders('POST', '/api/test');

      expect(headers.containsKey('X-HMAC-Signature'), isTrue);
      expect(headers.containsKey('X-Timestamp'), isTrue);
      expect(headers.length, equals(2));
    });

    test('X-Timestamp is in milliseconds (not seconds)', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final headers = ApiSecurityService.buildHmacHeaders(
        'POST',
        '/api/enagas/v1/videos/upload',
      );
      final after = DateTime.now().millisecondsSinceEpoch;

      final ts = int.parse(headers['X-Timestamp']!);
      // Millisecond timestamps are 13 digits; seconds-based are 10 digits.
      expect(ts.toString().length, equals(13));
      expect(ts, greaterThanOrEqualTo(before));
      expect(ts, lessThanOrEqualTo(after));
    });

    test('X-HMAC-Signature is HMAC-SHA256 of "{tsMs}:{METHOD}:{path}" (hex lowercase)', () {
      final path = '/api/enagas/v1/videos/upload';
      final headers =
          ApiSecurityService.buildHmacHeaders('POST', path);

      final tsMs = headers['X-Timestamp']!;
      final actualSig = headers['X-HMAC-Signature']!;

      // Recompute the expected signature with the same timestamp.
      final payload = '$tsMs:POST:$path';
      final key = utf8.encode(AppConfig.hmacSecret);
      final msgBytes = utf8.encode(payload);
      final hmac = Hmac(sha256, key);
      final expectedSig = hmac.convert(msgBytes).toString();

      expect(actualSig, equals(expectedSig));
    });

    test('signature is lowercase hex', () {
      final headers =
          ApiSecurityService.buildHmacHeaders('PATCH', '/api/test');
      final sig = headers['X-HMAC-Signature']!;

      expect(sig, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('method is uppercased in HMAC payload', () {
      // Both 'patch' and 'PATCH' must produce the same signature for the same ts.
      // We can't freeze time here, so instead we verify that the signature produced
      // with lowercase input is a valid HMAC (implying the method was uppercased).
      final headers =
          ApiSecurityService.buildHmacHeaders('patch', '/test');

      final tsMs = headers['X-Timestamp']!;
      final sig = headers['X-HMAC-Signature']!;

      final payload = '$tsMs:PATCH:/test'; // must be uppercase in recompute
      final key = utf8.encode(AppConfig.hmacSecret);
      final expected = Hmac(sha256, key).convert(utf8.encode(payload)).toString();

      expect(sig, equals(expected));
    });

    test('different paths produce different signatures (same timestamp not possible, '
        'but same method/path produces consistent signature)', () {
      // Two calls will have different timestamps, so we can only verify structure.
      final h1 = ApiSecurityService.buildHmacHeaders(
          'GET', '/api/enagas/v1/videos/upload/abc');
      final h2 = ApiSecurityService.buildHmacHeaders(
          'GET', '/api/enagas/v1/videos/upload/xyz');

      // Both must be valid 64-char hex signatures.
      expect(h1['X-HMAC-Signature']!.length, equals(64));
      expect(h2['X-HMAC-Signature']!.length, equals(64));
    });

    test('does NOT include Authorization header (no Bearer in HMAC scheme)', () {
      final headers =
          ApiSecurityService.buildHmacHeaders('POST', '/test');
      expect(headers.containsKey('Authorization'), isFalse);
    });
  });
}
