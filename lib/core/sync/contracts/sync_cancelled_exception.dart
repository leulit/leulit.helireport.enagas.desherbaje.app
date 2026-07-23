/// Thrown by a [RemoteAdapter] when it observes a cancelled `CancelToken`
/// mid-push (e.g. between chunks of a resumable video upload).
///
/// The engine recognises it exactly like [AuthExpiredException]: it aborts the
/// drain, but instead of dispatching an auth event it returns the in-flight job
/// to `pending` so a later send picks it up. Never treat it as a transport
/// failure — a cancelled job is not a failed job.
class SyncCancelledException implements Exception {
  const SyncCancelledException();

  @override
  String toString() => 'SyncCancelledException: envío cancelado por el usuario';
}
