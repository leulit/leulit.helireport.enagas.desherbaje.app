import '../contracts/syncable.dart';
import '../type_registry.dart';
import 'cancel_token.dart';
import 'pull_outcome.dart';

/// Carrier that pairs a remote item with the identity that should be used when
/// persisting it locally.
///
/// [clientId] is always the **local** client-id (canonical identity). When the
/// backend omits `client_id` from its response, [DetectConflictsTask] resolves
/// the correct identity by matching the remote's numeric id to an existing local
/// row, and stores that row's `clientId` here instead of the freshly minted UUID
/// from `fromJson`.
///
/// [local] is the current local copy (if any), carried forward so that
/// [EnqueueConflictsTask] does not have to perform an extra DB lookup (avoids
/// the N+1 pattern).
typedef ResolvedPullItem<T extends Syncable> = ({
  T remote,
  String clientId,
  T? local,
});

/// Describes a non-blocking per-item failure accumulated during the pull.
class PullTaskError {
  final String taskName;
  final Object error;

  const PullTaskError(this.taskName, this.error);

  @override
  String toString() => 'PullTaskError($taskName: $error)';
}

/// Mutable context that flows through the pull pipeline.
class PullContext<T extends Syncable> {
  final TypeRegistration<T> registration;
  final CancelToken? cancelToken;

  /// Set by [InvokeRemoteFetcherTask].
  List<T> remoteItems = const [];

  /// Set by [DetectConflictsTask]: items whose local copy diverges from
  /// remote and must be resolved by the user.
  final List<ResolvedPullItem<T>> conflicts = [];

  /// Set by [DetectConflictsTask]: items that can be persisted locally
  /// without further interaction.
  final List<ResolvedPullItem<T>> safeToUpsert = [];

  int upserted = 0;
  bool cancelled = false;

  /// Non-blocking per-item failures accumulated by [UpsertNonConflictingTask]
  /// and [EnqueueConflictsTask]. A non-empty list indicates a partial outcome:
  /// some items were persisted successfully, others were not.
  final List<PullTaskError> partialErrors = [];

  bool get hasPartialErrors => partialErrors.isNotEmpty;

  /// Set by [PullCoordinator] when the pipeline fails with a blocking error
  /// that is not a 401.
  Object? blockingError;

  /// Set by [PullCoordinator] when the pipeline fails with [AuthExpiredException].
  bool authExpired = false;

  PullContext({required this.registration, this.cancelToken});

  bool get isCancelRequested => cancelToken?.isCancelled ?? false;

  /// Human-readable error message derived from the current state. Null when
  /// the outcome is clean (ok or okWithConflicts).
  String? get errorMessage {
    if (authExpired) return 'La sesión ha caducado.';
    if (blockingError != null) return blockingError.toString();
    if (cancelled) return null;
    if (hasPartialErrors) {
      return partialErrors.map((e) => '[${e.taskName}] ${e.error}').join('; ');
    }
    return null;
  }

  /// Typed outcome with the following precedence:
  /// authExpired > blockingError > cancelled > partial > okWithConflicts > ok.
  PullOutcome get outcome {
    if (authExpired) return PullOutcome.authExpired;
    if (blockingError != null) return PullOutcome.error;
    if (cancelled) return PullOutcome.cancelled;
    if (hasPartialErrors) return PullOutcome.partial;
    if (conflicts.isNotEmpty) return PullOutcome.okWithConflicts;
    return PullOutcome.ok;
  }
}
