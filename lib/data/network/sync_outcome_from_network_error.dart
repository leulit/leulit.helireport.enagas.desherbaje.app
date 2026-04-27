import '../../core/sync/contracts/auth_expired_exception.dart';
import '../../core/sync/contracts/remote_adapter.dart';
import '../../core/sync/contracts/syncable.dart';
import 'network_error.dart';

/// Maps a transport-level [NetworkError] to a [SyncOutcome].
///
/// 401 is special-cased: it throws [AuthExpiredException] so the engine can
/// abort the whole drain and route the user to the login screen. Adapters
/// must let this exception propagate.
///
/// 409 is also special: [SyncConflict] requires a parsed `serverVersion`,
/// which only the concrete [RemoteAdapter] can build from the response
/// body. Adapters intercept conflicts before calling this helper.
SyncOutcome<T> syncOutcomeFromNetworkError<T extends Syncable>(
  NetworkError error,
) {
  if (error.statusCode == 401) {
    throw AuthExpiredException(error.message);
  }
  return switch (error.category) {
    NetworkErrorCategory.offline ||
    NetworkErrorCategory.timeout ||
    NetworkErrorCategory.retryable =>
      SyncRetryable<T>('${error.category.name}: ${error.message}'),
    NetworkErrorCategory.unauthorized ||
    NetworkErrorCategory.unrecoverable =>
      SyncUnrecoverable<T>(error.message, statusCode: error.statusCode),
    NetworkErrorCategory.conflict =>
      SyncUnrecoverable<T>(
        'Conflict without parsed server version: ${error.message}',
        statusCode: error.statusCode,
      ),
  };
}
