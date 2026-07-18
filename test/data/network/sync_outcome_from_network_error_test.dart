import 'package:flutter_test/flutter_test.dart';

import 'package:helireport_desherbaje/core/sync/contracts/remote_adapter.dart';
import 'package:helireport_desherbaje/data/network/network_error.dart';
import 'package:helireport_desherbaje/data/network/sync_outcome_from_network_error.dart';
import 'package:helireport_desherbaje/core/sync/contracts/syncable.dart';

// Minimal Syncable stub to satisfy the generic type parameter
class _FakeSyncable implements Syncable {
  @override
  String get clientId => 'fake-id';
  @override
  String? get remoteId => null;
  @override
  DateTime get updatedAt => DateTime.now();
  @override
  Map<String, dynamic> toJson() => {};
}

void main() {
  group('syncOutcomeFromNetworkError', () {
    NetworkError makeError(
      NetworkErrorCategory category, {
      int? statusCode,
      String message = 'error',
    }) =>
        NetworkError(category: category, statusCode: statusCode, message: message);

    // Un 401 es SIEMPRE fallo de firma HMAC, nunca sesión caducada: no puede
    // acabar en logout.
    test('returns SyncUnrecoverable for 401 (firma HMAC, no sesión)', () {
      final error = makeError(NetworkErrorCategory.unauthorized, statusCode: 401);
      final result = syncOutcomeFromNetworkError<_FakeSyncable>(error);
      expect(result, isA<SyncUnrecoverable<_FakeSyncable>>());
      expect((result as SyncUnrecoverable).statusCode, equals(401));
    });

    test('returns SyncRetryable for offline category', () {
      final result = syncOutcomeFromNetworkError<_FakeSyncable>(
        makeError(NetworkErrorCategory.offline),
      );
      expect(result, isA<SyncRetryable<_FakeSyncable>>());
    });

    test('returns SyncRetryable for timeout category', () {
      final result = syncOutcomeFromNetworkError<_FakeSyncable>(
        makeError(NetworkErrorCategory.timeout),
      );
      expect(result, isA<SyncRetryable<_FakeSyncable>>());
    });

    test('returns SyncRetryable for retryable category (5xx)', () {
      final result = syncOutcomeFromNetworkError<_FakeSyncable>(
        makeError(NetworkErrorCategory.retryable, statusCode: 503),
      );
      expect(result, isA<SyncRetryable<_FakeSyncable>>());
    });

    test('returns SyncUnrecoverable for 403', () {
      final result = syncOutcomeFromNetworkError<_FakeSyncable>(
        makeError(NetworkErrorCategory.unauthorized, statusCode: 403),
      );
      expect(result, isA<SyncUnrecoverable<_FakeSyncable>>());
      expect((result as SyncUnrecoverable).statusCode, equals(403));
    });

    test('returns SyncUnrecoverable for unrecoverable category (422)', () {
      final result = syncOutcomeFromNetworkError<_FakeSyncable>(
        makeError(NetworkErrorCategory.unrecoverable, statusCode: 422),
      );
      expect(result, isA<SyncUnrecoverable<_FakeSyncable>>());
    });

    test('returns SyncUnrecoverable for conflict category without parsed version', () {
      final result = syncOutcomeFromNetworkError<_FakeSyncable>(
        makeError(NetworkErrorCategory.conflict, statusCode: 409),
      );
      expect(result, isA<SyncUnrecoverable<_FakeSyncable>>());
    });

    test('SyncRetryable message includes category name', () {
      final result = syncOutcomeFromNetworkError<_FakeSyncable>(
        makeError(NetworkErrorCategory.offline, message: 'no network'),
      );
      final retryable = result as SyncRetryable<_FakeSyncable>;
      expect(retryable.reason, contains('offline'));
      expect(retryable.reason, contains('no network'));
    });
  });
}
