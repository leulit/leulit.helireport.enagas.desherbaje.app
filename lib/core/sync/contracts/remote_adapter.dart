import 'sync_job.dart';
import 'syncable.dart';

sealed class SyncOutcome<T extends Syncable> {
  const SyncOutcome();
}

final class SyncSuccess<T extends Syncable> extends SyncOutcome<T> {
  final String? remoteId;
  final T? serverVersion;
  const SyncSuccess({this.remoteId, this.serverVersion});
}

final class SyncRetryable<T extends Syncable> extends SyncOutcome<T> {
  final String reason;
  const SyncRetryable(this.reason);
}

final class SyncUnrecoverable<T extends Syncable> extends SyncOutcome<T> {
  final String reason;
  final int? statusCode;
  const SyncUnrecoverable(this.reason, {this.statusCode});
}

final class SyncConflict<T extends Syncable> extends SyncOutcome<T> {
  final T serverVersion;
  const SyncConflict(this.serverVersion);
}

/// Contract implemented by each entity's remote adapter.
///
/// Implementations live in the data layer and use the project's
/// `NetworkService` facade. They translate transport errors into
/// [SyncOutcome] via `syncOutcomeFromNetworkError`, except for
/// [SyncConflict] — which requires parsing the response body to recover
/// the server version and must be built explicitly.
abstract class RemoteAdapter<T extends Syncable> {
  Future<SyncOutcome<T>> push({
    required T entity,
    required SyncOperation operation,
  });
}
