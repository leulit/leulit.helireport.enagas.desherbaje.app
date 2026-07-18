// Tests for adapter_support.dart — extractRemoteIntId, parseRemoteId,
// bodyIndicatesError, bodyErrorMessage.
import 'package:flutter_test/flutter_test.dart';

import 'package:helireport_desherbaje/data/sync/adapter_support.dart';

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

  // ─── bodyIndicatesError ────────────────────────────────────────────────────

  group('bodyIndicatesError', () {
    test('false for non-map / null', () {
      expect(bodyIndicatesError(null), isFalse);
      expect(bodyIndicatesError('x'), isFalse);
      expect(bodyIndicatesError(42), isFalse);
    });

    test('false for a normal OK body', () {
      expect(bodyIndicatesError({'id': 1, 'ok': true}), isFalse);
      expect(bodyIndicatesError({'data': 'whatever'}), isFalse);
    });

    test('true when ok:false or success:false', () {
      expect(bodyIndicatesError({'ok': false}), isTrue);
      expect(bodyIndicatesError({'success': false}), isTrue);
    });

    test('true when error / error_message / errorMessage non-empty', () {
      expect(bodyIndicatesError({'error': 'boom'}), isTrue);
      expect(bodyIndicatesError({'error_message': 'boom'}), isTrue);
      expect(bodyIndicatesError({'errorMessage': 'boom'}), isTrue);
      expect(bodyIndicatesError({'error': {'code': 1}}), isTrue);
      expect(bodyIndicatesError({'error': ['x']}), isTrue);
    });

    test('false when error present but empty', () {
      expect(bodyIndicatesError({'error': ''}), isFalse);
      expect(bodyIndicatesError({'error': const <String, dynamic>{}}), isFalse);
      expect(bodyIndicatesError({'error': const []}), isFalse);
    });
  });

  // ─── bodyErrorMessage ──────────────────────────────────────────────────────

  group('bodyErrorMessage', () {
    test('null for non-map / no error', () {
      expect(bodyErrorMessage(null), isNull);
      expect(bodyErrorMessage({'ok': true}), isNull);
    });

    test('returns string error', () {
      expect(bodyErrorMessage({'error': 'boom'}), equals('boom'));
      expect(bodyErrorMessage({'error_message': 'x'}), equals('x'));
    });

    test('returns nested error.message', () {
      expect(
        bodyErrorMessage({'error': {'message': 'nested'}}),
        equals('nested'),
      );
    });
  });
}
