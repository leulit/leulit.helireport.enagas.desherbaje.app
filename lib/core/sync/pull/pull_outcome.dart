/// Typed outcome of a pull operation.
///
/// The string representations follow snake_case so they can be written
/// directly into `pull_state.last_status` without additional mapping.
enum PullOutcome {
  ok,
  okWithConflicts,
  partial,
  error,
  cancelled,
  authExpired;

  /// Snake-case string stored in `pull_state.last_status`.
  String get statusString => switch (this) {
        PullOutcome.ok => 'ok',
        PullOutcome.okWithConflicts => 'ok_with_conflicts',
        PullOutcome.partial => 'partial',
        PullOutcome.error => 'error',
        PullOutcome.cancelled => 'cancelled',
        PullOutcome.authExpired => 'auth_expired',
      };
}
