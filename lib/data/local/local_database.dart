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
  static Future<Database>? _initFuture;

  LocalDatabase._();
  static LocalDatabase get instance => _instance ??= LocalDatabase._();

  Future<Database> get database async {
    // 1. Si la DB ya está abierta, devolverla
    if (_db != null) return _db!;

    // 2. Si ya hay una inicialización en curso, esperar a esa misma
    if (_initFuture != null) return await _initFuture!;

    // 3. Si no hay nada, creamos el futuro de inicialización
    _initFuture = _initDb();
    
    try {
      _db = await _initFuture;
      return _db!;
    } finally {
      // Limpiamos el futuro al terminar para permitir reintentos si falló
      _initFuture = null; 
    }
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final fullPath = path.join(dbPath, 'helireport_desherbaje.db');
    final db = await OfflineDatabase.open(fullPath);
    await _createMasterDataTables(db);
    return db;
  }

  Future<void> hardResetGasoductos() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.execute('DROP TABLE IF EXISTS gasoductos');
      // Volvemos a ejecutar la creación específica para esa tabla
      await txn.execute('''
        CREATE TABLE gasoductos (
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
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_gasoductos_ct ON gasoductos(ct_id)',
      );
    });
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
