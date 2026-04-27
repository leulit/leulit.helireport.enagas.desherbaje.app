import 'syncable.dart';

/// Decides how to reconcile a divergence between the local copy of an entity
/// and the version coming from the server (either via 409 on push or via
/// `localUpdatedAt > remoteUpdatedAt` on pull / outbox-pending divergence).
///
/// Implementations are stateless and must be safe to share across calls.
/// A `null` return value is the explicit signal "I cannot decide; defer to
/// the user" — only [InteractiveConflictResolver] uses it.
abstract class ConflictResolver<T extends Syncable> {
  /// Returns the version that should be persisted locally, or `null` to
  /// hand off the decision to the user (the engine enqueues a row in
  /// `sync_conflicts`).
  T? resolve({required T local, required T remote});
}

/// Cloud is the source of truth. Used for read-only master data
/// (`Gasoducto`, `PK`, …) where the operator never edits.
class ServerWinsResolver<T extends Syncable> implements ConflictResolver<T> {
  const ServerWinsResolver();

  @override
  T resolve({required T local, required T remote}) => remote;
}

/// Local always wins. Rare; reserve for cases where the operator's offline
/// observation is authoritative regardless of backend state.
class LocalWinsResolver<T extends Syncable> implements ConflictResolver<T> {
  const LocalWinsResolver();

  @override
  T resolve({required T local, required T remote}) => local;
}

/// Compares timestamps. Useful for append-only / log-style entities where
/// the freshest write is the correct one.
class LastWriteWinsResolver<T extends Syncable> implements ConflictResolver<T> {
  const LastWriteWinsResolver();

  @override
  T resolve({required T local, required T remote}) =>
      local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
}

/// Defers the decision to the user. The engine enqueues the divergence in
/// `sync_conflicts` and the sync page renders a diff for the operator to
/// resolve.
class InteractiveConflictResolver<T extends Syncable>
    implements ConflictResolver<T> {
  const InteractiveConflictResolver();

  @override
  T? resolve({required T local, required T remote}) => null;
}
