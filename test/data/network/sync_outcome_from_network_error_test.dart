import 'package:flutter_test/flutter_test.dart';
import 'package:helireport_desherbaje/core/sync/contracts/remote_adapter.dart';
import 'package:helireport_desherbaje/core/sync/contracts/syncable.dart';
import 'package:helireport_desherbaje/data/network/network_error.dart';
import 'package:helireport_desherbaje/data/network/sync_outcome_from_network_error.dart';

class _Stub implements Syncable {
  @override
  final String clientId;
  @override
  final String? remoteId;
  @override
  final DateTime updatedAt;
  _Stub(this.clientId, {this.remoteId, DateTime? updatedAt})
      : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  @override
  Map<String, dynamic> toJson() => {'client_id': clientId};
}

void main() {
  NetworkError err(NetworkErrorCategory c, {int? status}) => NetworkError(
        category: c,
        message: 'm',
        statusCode: status,
      );

  test('offline → SyncRetryable', () {
    final out = syncOutcomeFromNetworkError<_Stub>(err(NetworkErrorCategory.offline));
    expect(out, isA<SyncRetryable<_Stub>>());
  });

  test('timeout → SyncRetryable', () {
    final out = syncOutcomeFromNetworkError<_Stub>(err(NetworkErrorCategory.timeout));
    expect(out, isA<SyncRetryable<_Stub>>());
  });

  test('retryable (5xx) → SyncRetryable', () {
    final out = syncOutcomeFromNetworkError<_Stub>(
        err(NetworkErrorCategory.retryable, status: 502));
    expect(out, isA<SyncRetryable<_Stub>>());
  });

  test('unauthorized → SyncUnrecoverable carrying statusCode', () {
    final out = syncOutcomeFromNetworkError<_Stub>(
        err(NetworkErrorCategory.unauthorized, status: 401));
    expect(out, isA<SyncUnrecoverable<_Stub>>());
    expect((out as SyncUnrecoverable<_Stub>).statusCode, 401);
  });

  test('unrecoverable (4xx) → SyncUnrecoverable carrying statusCode', () {
    final out = syncOutcomeFromNetworkError<_Stub>(
        err(NetworkErrorCategory.unrecoverable, status: 422));
    expect(out, isA<SyncUnrecoverable<_Stub>>());
    expect((out as SyncUnrecoverable<_Stub>).statusCode, 422);
  });

  test('conflict (without parsed body) → SyncUnrecoverable fallback', () {
    final out = syncOutcomeFromNetworkError<_Stub>(
        err(NetworkErrorCategory.conflict, status: 409));
    expect(out, isA<SyncUnrecoverable<_Stub>>());
    expect((out as SyncUnrecoverable<_Stub>).reason,
        contains('Conflict without parsed server version'));
  });
}
