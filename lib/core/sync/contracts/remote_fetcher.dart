import 'syncable.dart';

/// Pulls the full backend dataset for a single entity type. One implementation
/// per pulleable entity. Optional in [TypeRegistration] — entities without a
/// fetcher are write-only.
///
/// The fetcher returns the **full** authoritative set: there is no delta
/// (`since`) nor cursor pagination. The client downloads everything when the
/// user asks for it from the sync page.
///
/// Errors propagate to the [PullCoordinator], which turns them into a failed
/// [PullOutcome]. A 401 must NOT be treated as session expiry: on an HMAC-only
/// transport it is a signature failure (wrong secret, skewed device clock,
/// badly signed path), so it must never trigger a logout — that would destroy
/// the operator's field session over a problem they cannot diagnose. Fetchers
/// rethrow it as a plain transport error.
abstract class RemoteFetcher<T extends Syncable> {
  Future<List<T>> pullAll();
}
