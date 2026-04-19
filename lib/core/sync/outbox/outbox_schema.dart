import 'package:sqflite/sqflite.dart';

abstract class OutboxSchema {
  static const tableName = 'sync_queue';

  static const _createTable = '''
    CREATE TABLE IF NOT EXISTS $tableName (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type  TEXT    NOT NULL,
      entity_id    TEXT    NOT NULL,
      operation    TEXT    NOT NULL,
      status       TEXT    NOT NULL DEFAULT 'pending',
      attempts     INTEGER NOT NULL DEFAULT 0,
      last_error   TEXT,
      payload      TEXT,
      created_at   INTEGER NOT NULL,
      synced_at    INTEGER,
      remote_id    TEXT,
      UNIQUE(entity_type, entity_id, operation)
    )
  ''';

  static const _indexStatus =
      'CREATE INDEX IF NOT EXISTS idx_${tableName}_status ON $tableName(status)';

  static const _indexType =
      'CREATE INDEX IF NOT EXISTS idx_${tableName}_type ON $tableName(entity_type, status)';

  static Future<void> ensure(Database db) async {
    await db.execute(_createTable);
    await db.execute(_indexStatus);
    await db.execute(_indexType);
  }
}
