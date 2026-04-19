import '../../core/sync/contracts/remote_adapter.dart';
import '../../core/sync/contracts/syncable.dart';
import 'network_error.dart';

/// Maps a transport-level [NetworkError] to a [SyncOutcome].
///
/// Covers everything except `conflict`: [SyncConflict] requires a parsed
/// `serverVersion`, which only the concrete [RemoteAdapter] can build from
/// the response body. Adapters must intercept [NetworkErrorCategory.conflict]
/// before calling this helper and return [SyncConflict] explicitly.
SyncOutcome<T> syncOutcomeFromNetworkError<T extends Syncable>(
  NetworkError error,
) {
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
