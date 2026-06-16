// Tests for adapter_support.dart — extractRemoteIntId, parseRemoteId,
// bearerAuthHeader.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:helireport_desherbaje/data/sync/adapter_support.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  // ─── extractRemoteIntId ────────────────────────────────────────────────────

  group('extractRemoteIntId', () {
    test('returns value under "id" when present as int', () {
      expect(extractRemoteIntId({'id': 42}), equals(42));
    });

    test('returns value under "id" when present as num', () {
      expect(extractRemoteIntId({'id': 42.0}), equals(42));
    });

    test('returns value under "id" when present as parseable String', () {
      expect(extractRemoteIntId({'id': '42'}), equals(42));
    });

    test('"id" takes priority over "remote_id"', () {
      expect(extractRemoteIntId({'id': 1, 'remote_id': 99}), equals(1));
    });

    test('"remote_id" used when "id" absent', () {
      expect(extractRemoteIntId({'remote_id': 5}), equals(5));
    });

    test('"remoteId" used as third priority', () {
      expect(extractRemoteIntId({'remoteId': 7}), equals(7));
    });

    test('"itemId" used as fourth priority', () {
      expect(extractRemoteIntId({'itemId': 3}), equals(3));
    });

    test('returns null when no known key is present', () {
      expect(extractRemoteIntId({'other_key': 99}), isNull);
    });

    test('returns null when map is empty', () {
      expect(extractRemoteIntId({}), isNull);
    });

    test('returns null when value is non-numeric string', () {
      expect(extractRemoteIntId({'id': 'not-a-number'}), isNull);
    });

    test('custom key list is respected', () {
      expect(
        extractRemoteIntId({'custom_id': 77}, keys: const ['custom_id']),
        equals(77),
      );
    });
  });

  // ─── parseRemoteId ─────────────────────────────────────────────────────────

  group('parseRemoteId', () {
    test("'5' parses to 5", () {
      expect(parseRemoteId('5'), equals(5));
    });

    test("'0' parses to 0", () {
      expect(parseRemoteId('0'), equals(0));
    });

    test("'abc' returns null", () {
      expect(parseRemoteId('abc'), isNull);
    });

    test('null returns null', () {
      expect(parseRemoteId(null), isNull);
    });

    test('empty string returns null', () {
      expect(parseRemoteId(''), isNull);
    });
  });

  // ─── bearerAuthHeader ──────────────────────────────────────────────────────

  group('bearerAuthHeader', () {
    late _MockSecureStorage storage;

    setUp(() {
      storage = _MockSecureStorage();
    });

    test('returns null when no token is stored', () async {
      when(() => storage.read(key: 'auth_token')).thenAnswer((_) async => null);

      final result = await bearerAuthHeader(storage);
      expect(result, isNull);
    });

    test('returns Authorization header when token is stored', () async {
      when(() => storage.read(key: 'auth_token'))
          .thenAnswer((_) async => 'my-test-token');

      final result = await bearerAuthHeader(storage);
      expect(result, isNotNull);
      expect(result!['Authorization'], equals('Bearer my-test-token'));
    });

    test('respects custom key param', () async {
      when(() => storage.read(key: 'custom_key'))
          .thenAnswer((_) async => 'custom-token');

      final result = await bearerAuthHeader(storage, key: 'custom_key');
      expect(result!['Authorization'], equals('Bearer custom-token'));
    });
  });
}
