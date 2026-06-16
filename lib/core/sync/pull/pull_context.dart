import '../contracts/syncable.dart';
import '../type_registry.dart';
import 'cancel_token.dart';

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

  PullContext({required this.registration, this.cancelToken});

  bool get isCancelRequested => cancelToken?.isCancelled ?? false;
}
