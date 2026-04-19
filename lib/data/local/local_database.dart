import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../core/sync/sync.dart';

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
    return openDatabase(
      fullPath,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE actividades (
        id              INTEGER PRIMARY KEY,
        posicion_id     INTEGER NOT NULL DEFAULT 0,
        estado          TEXT NOT NULL DEFAULT 'Propuesta',
        descripcion     TEXT NOT NULL DEFAULT '',
        superficie_m2   REAL NOT NULL DEFAULT 0.0,
        coste_estimado  REAL NOT NULL DEFAULT 0.0,
        fecha_programada TEXT,
        fecha_inicio    TEXT,
        fecha_fin       TEXT,
        segmentos_json  TEXT,
        synced_at       TEXT,
        needs_sync      INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE imagenes_actividad (
        local_id        TEXT PRIMARY KEY,
        remote_id       INTEGER,
        actividad_id    INTEGER NOT NULL,
        segmento_id     INTEGER,
        local_path      TEXT NOT NULL,
        remote_url      TEXT,
        tipo_foto       TEXT NOT NULL,
        captured_at     TEXT NOT NULL,
        latitude        REAL,
        longitude       REAL,
        sync_status     TEXT NOT NULL DEFAULT 'pending',
        created_at      TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_imagenes_actividad ON imagenes_actividad(actividad_id)',
    );
    await db.execute(
      'CREATE INDEX idx_imagenes_sync ON imagenes_actividad(sync_status)',
    );

    await db.execute('''
      CREATE TABLE gasoductos (
        id          TEXT NOT NULL,
        nombre      TEXT NOT NULL DEFAULT '',
        ct          TEXT NOT NULL,
        points_json TEXT NOT NULL,
        color_value INTEGER NOT NULL DEFAULT 4283122624,
        stroke_width REAL NOT NULL DEFAULT 3.0,
        synced_at   TEXT NOT NULL DEFAULT (datetime('now')),
        PRIMARY KEY (id, ct)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_gasoductos_ct ON gasoductos(ct)',
    );

    await OutboxSchema.ensure(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS gasoductos (
          id          TEXT NOT NULL,
          nombre      TEXT NOT NULL DEFAULT '',
          ct          TEXT NOT NULL,
          points_json TEXT NOT NULL,
          color_value INTEGER NOT NULL DEFAULT 4283122624,
          stroke_width REAL NOT NULL DEFAULT 3.0,
          synced_at   TEXT NOT NULL DEFAULT (datetime('now')),
          PRIMARY KEY (id, ct)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_gasoductos_ct ON gasoductos(ct)',
      );
    }
    if (oldVersion < 3) {
      // tipo_actividad se elimina de actividades (ahora está en cada segmento).
      // ALTER TABLE ... DROP COLUMN requiere SQLite ≥3.35; se envuelve en try/catch
      // para compatibilidad con versiones antiguas de Android (el dato queda obsoleto
      // pero no causa errores).
      try {
        await db.execute('ALTER TABLE actividades DROP COLUMN tipo_actividad');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      await OutboxSchema.ensure(db);
    }
  }
}
