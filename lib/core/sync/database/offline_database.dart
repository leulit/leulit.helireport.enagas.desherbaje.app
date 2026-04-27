import 'package:sqflite/sqflite.dart';

import '../contracts/local_store.dart';

/// Owns the SQLite connection used by the offline-first engine.
///
/// Responsibilities at startup:
/// 1. Open the database with WAL + foreign-keys ON.
/// 2. Guarantee the infrastructure tables (`_entity_schema_version`,
///    `sync_queue`, `sync_conflicts`, `pull_state`).
/// 3. Reclaim orphaned outbox jobs left in `syncing` from a previous session
///    (`UPDATE sync_queue SET status='pending' WHERE status='syncing'`) —
///    relies on backend idempotency by `client_id` to keep retries safe.
///
/// Per-entity migrations are executed by [migrateEntity], called from
/// `OfflineModule.registerEntity` so each store evolves its schema
/// independently of the others.
abstract class OfflineDatabase {
  static const String entitySchemaVersionTable = '_entity_schema_version';
  static const String syncQueueTable = 'sync_queue';
  static const String syncConflictsTable = 'sync_conflicts';
  static const String pullStateTable = 'pull_state';

  static Future<Database> open(String path) async {
    final db = await openDatabase(path, onConfigure: _configure);
    await _ensureInfraTables(db);
    await _reclaimOrphanedJobs(db);
    return db;
  }

  /// Brings a single entity's schema up to its declared `schemaVersion`.
  /// Idempotent: a second call after the version has been bumped is a no-op.
  static Future<void> migrateEntity<T>(
    Database db,
    LocalStore store,
  ) async {
    final current = await _readVersion(db, store.entityType);
    final target = store.schemaVersion;
    if (current == target) return;
    if (current > target) {
      throw StateError(
        'Entity "${store.entityType}" persisted version ($current) is greater '
        'than declared schemaVersion ($target). Downgrades are not supported.',
      );
    }
    await store.migrate(db, current, target);
    await _writeVersion(db, store.entityType, target);
  }

  static Future<void> _configure(Database db) async {
    // PRAGMA journal_mode returns a row with the applied mode; sqflite on
    // iOS surfaces that as an error when called via `execute`. Use rawQuery.
    await db.rawQuery('PRAGMA journal_mode = WAL');
    await db.rawQuery('PRAGMA foreign_keys = ON');
  }

  static Future<void> _ensureInfraTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $entitySchemaVersionTable (
        entity_type TEXT PRIMARY KEY,
        version     INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $syncQueueTable (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type  TEXT    NOT NULL,
        client_id    TEXT    NOT NULL,
        operation    TEXT    NOT NULL,
        status       TEXT    NOT NULL DEFAULT 'pending',
        attempts     INTEGER NOT NULL DEFAULT 0,
        last_error   TEXT,
        status_code  INTEGER,
        remote_id    TEXT,
        created_at   INTEGER NOT NULL,
        synced_at    INTEGER,
        UNIQUE(entity_type, client_id, operation)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${syncQueueTable}_status '
      'ON $syncQueueTable(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${syncQueueTable}_entity '
      'ON $syncQueueTable(entity_type, status)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $syncConflictsTable (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type  TEXT    NOT NULL,
        client_id    TEXT    NOT NULL,
        local_json   TEXT    NOT NULL,
        remote_json  TEXT    NOT NULL,
        detected_at  INTEGER NOT NULL,
        UNIQUE(entity_type, client_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${syncConflictsTable}_entity '
      'ON $syncConflictsTable(entity_type)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $pullStateTable (
        entity_type    TEXT    PRIMARY KEY,
        last_pulled_at INTEGER,
        last_status    TEXT,
        last_error     TEXT
      )
    ''');
  }

  static Future<void> _reclaimOrphanedJobs(Database db) async {
    await db.update(
      syncQueueTable,
      {'status': 'pending'},
      where: 'status = ?',
      whereArgs: ['syncing'],
    );
  }

  static Future<int> _readVersion(Database db, String entityType) async {
    final rows = await db.query(
      entitySchemaVersionTable,
      where: 'entity_type = ?',
      whereArgs: [entityType],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return rows.first['version']! as int;
  }

  static Future<void> _writeVersion(
    Database db,
    String entityType,
    int version,
  ) async {
    await db.insert(
      entitySchemaVersionTable,
      {'entity_type': entityType, 'version': version},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
