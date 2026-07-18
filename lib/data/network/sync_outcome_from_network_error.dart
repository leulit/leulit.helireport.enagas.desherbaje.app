import '../../core/app_log.dart';
import '../../core/sync/contracts/remote_adapter.dart';
import '../../core/sync/contracts/syncable.dart';
import 'network_error.dart';

/// Maps a transport-level [NetworkError] to a [SyncOutcome].
///
/// 401/403 no es expiración de sesión: esta API no tiene sesión ni Bearer, la
/// firma HMAC es la única autenticación (§1 del contrato). Un 401 significa
/// secreto erróneo, reloj del dispositivo desfasado >5 min o path mal firmado.
/// Se mapea a [SyncUnrecoverable] — deslogar al operador destruiría su sesión
/// de campo por un problema que no puede diagnosticar.
///
/// 409 is also special: [SyncConflict] requires a parsed `serverVersion`,
/// which only the concrete [RemoteAdapter] can build from the response
/// body. Adapters intercept conflicts before calling this helper.
SyncOutcome<T> syncOutcomeFromNetworkError<T extends Syncable>(
  NetworkError error,
) {
  if (error.category == NetworkErrorCategory.unauthorized) {
    AppLog.e(
      'HMAC signature rejected (HTTP ${error.statusCode}) — check HMAC_SECRET '
      'and device clock (signature window is ±5 min): ${error.message}',
    );
    return SyncUnrecoverable<T>(
      'Firma HMAC rechazada (HTTP ${error.statusCode}) — revisa HMAC_SECRET y '
      'la hora del dispositivo.',
      statusCode: error.statusCode,
    );
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
