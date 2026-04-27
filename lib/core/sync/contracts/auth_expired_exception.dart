/// Thrown by a [RemoteAdapter] or [RemoteFetcher] (or by the underlying
/// transport layer that they rely on) when the server responds with 401.
///
/// Catching this exception is the [SyncEngine]'s responsibility: it aborts
/// the current drain and dispatches `SyncActions.authExpired` so the app
/// can navigate the user to the login screen.
class AuthExpiredException implements Exception {
  final String reason;

  const AuthExpiredException([this.reason = 'Authentication token expired']);

  @override
  String toString() => 'AuthExpiredException: $reason';
}
