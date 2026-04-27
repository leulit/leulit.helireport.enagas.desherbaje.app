import '../contracts/syncable.dart';
import '../type_registry.dart';
import 'cancel_token.dart';

/// Mutable context that flows through the pull pipeline.
class PullContext<T extends Syncable> {
  final TypeRegistration<T> registration;
  final CancelToken? cancelToken;

  /// Set by [InvokeRemoteFetcherTask].
  List<T> remoteItems = const [];

  /// Set by [DetectConflictsTask]: items whose local copy diverges from
  /// remote and must be resolved by the user.
  final List<T> conflicts = [];

  /// Set by [DetectConflictsTask]: items that can be persisted locally
  /// without further interaction.
  final List<T> safeToUpsert = [];

  int upserted = 0;
  bool cancelled = false;

  PullContext({required this.registration, this.cancelToken});

  bool get isCancelRequested => cancelToken?.isCancelled ?? false;
}
