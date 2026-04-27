import 'syncable.dart';

/// Pulls the full backend dataset for a single entity type. One implementation
/// per pulleable entity. Optional in [TypeRegistration] — entities without a
/// fetcher are write-only.
///
/// The fetcher returns the **full** authoritative set: there is no delta
/// (`since`) nor cursor pagination. The client downloads everything when the
/// user asks for it from the sync page.
///
/// Should let [AuthExpiredException] propagate if the transport returns 401.
abstract class RemoteFetcher<T extends Syncable> {
  Future<List<T>> pullAll();
}
