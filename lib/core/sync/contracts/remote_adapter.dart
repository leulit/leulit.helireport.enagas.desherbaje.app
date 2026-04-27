import 'sync_job.dart';
import 'syncable.dart';

/// Outcome of a single push attempt by a [RemoteAdapter].
sealed class SyncOutcome<T extends Syncable> {
  const SyncOutcome();
}

/// The backend accepted the push.
final class SyncSuccess<T extends Syncable> extends SyncOutcome<T> {
  /// Backend-assigned identifier (if returned).
  final String? remoteId;

  /// Optional server-side version of the entity, returned in the response
  /// body. When provided the local store is overwritten with it so the
  /// client picks up backend-mutated fields (timestamps, derived data, …).
  final T? serverVersion;

  const SyncSuccess({this.remoteId, this.serverVersion});
}

/// Transient failure: network down, 5xx, 408, 429. The job stays pending and
/// the user can retry later.
final class SyncRetryable<T extends Syncable> extends SyncOutcome<T> {
  final String reason;

  const SyncRetryable(this.reason);
}

/// Permanent failure: the backend rejected the payload (4xx semantic).
/// Retrying with the same payload will fail the same way; the user must
/// edit the entity or discard the job.
///
/// [errorMessageEs] carries the human-readable message coming from the
/// backend (`error_message` field in the response). It is shown verbatim
/// to the operator in the "Subidas rechazadas" sublist.
final class SyncUnrecoverable<T extends Syncable> extends SyncOutcome<T> {
  final String reason;
  final int? statusCode;
  final String? errorMessageEs;

  const SyncUnrecoverable(
    this.reason, {
    this.statusCode,
    this.errorMessageEs,
  });
}

/// The backend reports that its version diverged from the client's
/// (HTTP 409). The server's version travels in [serverVersion] and the
/// client routes the case through its [ConflictResolver].
final class SyncConflict<T extends Syncable> extends SyncOutcome<T> {
  final T serverVersion;

  const SyncConflict(this.serverVersion);
}

/// Pushes a single entity to the backend. One implementation per entity type.
///
/// The adapter is responsible for translating transport-layer errors into
/// the appropriate [SyncOutcome] subtype. The single exception is
/// [AuthExpiredException]: the adapter should let it propagate so the
/// engine can abort the drain.
abstract class RemoteAdapter<T extends Syncable> {
  Future<SyncOutcome<T>> push({
    required T entity,
    required SyncOperation operation,
  });
}
