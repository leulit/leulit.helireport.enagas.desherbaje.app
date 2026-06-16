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

  Future<List<T>> findAll();

  Future<void> markSynced({
    required String clientId,
    String? remoteId,
    DatabaseExecutor? txn,
  });
}
