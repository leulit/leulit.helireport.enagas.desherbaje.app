import 'package:sqflite/sqflite.dart';

import 'syncable.dart';

/// Persists entities of type [T] in the local SQLite database and owns the
/// schema for that entity. Each [LocalStore] declares its own [schemaVersion]
/// and runs its own [migrate] in isolation from the other entities — there is
/// no global database version.
abstract class LocalStore<T extends Syncable> {
  /// Stable string identifier used in the outbox, type registry and
  /// `_entity_schema_version` table. Must be unique across the app.
  String get entityType;

  /// Current schema version owned by this store. Increment when the table
  /// definition changes and add the corresponding branch in [migrate].
  int get schemaVersion;

  /// Brings this entity's schema from [from] to [to]. Called by
  /// `OfflineDatabase.migrateEntity` inside a transaction; receives the
  /// transaction executor so DDL and version tracking are atomic.
  ///
  /// - When [from] is `0` the entity has never been installed: create the
  ///   table from scratch.
  /// - When [from] > 0 evolve the schema with `ALTER TABLE` / data backfill.
  /// - [to] is always equal to [schemaVersion].
  /// - [db] is a [DatabaseExecutor] (either a [Transaction] or a [Database]);
  ///   use only methods available on that interface (`execute`, `rawQuery`, …).
  Future<void> migrate(DatabaseExecutor db, int from, int to);

  Future<void> upsert(T entity, {DatabaseExecutor? txn});

  Future<void> delete(String clientId, {DatabaseExecutor? txn});

  Future<T?> findByClientId(String clientId);

  /// Looks up an entity by its backend-assigned remote id.
  ///
  /// [remoteId] is the string representation of whatever the backend returns
  /// (e.g. `"42"` for a numeric INTEGER column). The implementation is
  /// responsible for any parsing — stores whose primary key is non-numeric
  /// should return `null` for strings that cannot be coerced.
  ///
  /// Returns `null` if the entity has not been pulled yet or the store does
  /// not track a remote id (push-only stores may always return `null`).
  Future<T?> findByRemoteId(String remoteId);

  Future<List<T>> findAll();

  /// Returns all entities where [column] equals [value].
  ///
  /// **[column] MUST be a code literal, never user input** — the value is
  /// interpolated directly into the SQL WHERE clause. Callers that pass a
  /// user-controlled string open an SQL-injection surface.
  ///
  /// Implementations SHOULD apply the same `orderBy` as their [findAll].
  Future<List<T>> findWhere(String column, Object? value);

  Future<void> markSynced({
    required String clientId,
    String? remoteId,
    DatabaseExecutor? txn,
  });
}
