import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../core/sync/sync.dart';

/// Thin wrapper that opens the SQLite database via [OfflineDatabase] and
/// adds project-specific master-data tables that are not yet modelled as
/// sync engine entities (`gasoductos`, `pks`). Once those become regular
/// `LocalStore`s the wrapper here can shrink to a single line.
class LocalDatabase {
  static LocalDatabase? _instance;
  static Database? _db;

  LocalDatabase._();
  static LocalDatabase get instance => _instance ??= LocalDatabase._();

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final fullPath = path.join(dbPath, 'helireport_desherbaje.db');
    final db = await OfflineDatabase.open(fullPath);
    await _createMasterDataTables(db);
    return db;
  }

  Future<void> _createMasterDataTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS gasoductos (
        id           TEXT NOT NULL,
        nombre       TEXT NOT NULL DEFAULT '',
        ct_id        INTEGER NOT NULL,
        points_json  TEXT NOT NULL,
        color_value  INTEGER NOT NULL DEFAULT 4283122624,
        stroke_width REAL NOT NULL DEFAULT 3.0,
        synced_at    TEXT NOT NULL DEFAULT (datetime('now')),
        PRIMARY KEY (id, ct_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_gasoductos_ct ON gasoductos(ct_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pks (
        id        TEXT NOT NULL,
        ct_id     INTEGER NOT NULL,
        label     TEXT NOT NULL DEFAULT '',
        lat       REAL NOT NULL,
        lng       REAL NOT NULL,
        synced_at TEXT NOT NULL DEFAULT (datetime('now')),
        PRIMARY KEY (id, ct_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pks_ct ON pks(ct_id)',
    );
  }
}
