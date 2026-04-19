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
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createSegmentosTable(db);
    await _createImagenesTable(db);
    await _createGasoductosTable(db);
    await OutboxSchema.ensure(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createGasoductosTable(db);
    }
    if (oldVersion < 4) {
      await OutboxSchema.ensure(db);
    }
    if (oldVersion < 5) {
      // Refactor ActividadEntity → SegmentoEntity: sustituimos la tabla
      // `actividades` (con `segmentos_json` denormalizado) por una tabla
      // `segmentos` plana. Los registros en la caché local se pierden; el
      // backend es fuente de verdad. Los jobs de outbox huérfanos se purgan
      // para evitar que el SyncEngine falle al no encontrar el registro.
      await db.execute('DROP TABLE IF EXISTS actividades');
      await db.delete(
        'sync_queue',
        where: 'entity_type = ?',
        whereArgs: ['actividad'],
      );
      await _createSegmentosTable(db);
    }
  }

  Future<void> _createSegmentosTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS segmentos (
        id                INTEGER PRIMARY KEY,
        ct_id             INTEGER NOT NULL DEFAULT 0,
        nombre            TEXT,
        descripcion       TEXT NOT NULL DEFAULT '',
        traza             TEXT,
        tipo_instalacion  TEXT NOT NULL DEFAULT 'lineal',
        pk_inicio         REAL,
        pk_fin            REAL,
        lat_inicio        REAL,
        lng_inicio        REAL,
        lat_fin           REAL,
        lng_fin           REAL,
        ubicacion_gis     TEXT,
        tipo_actividad    TEXT NOT NULL DEFAULT 'desherbaje_selectivo',
        estado            TEXT NOT NULL DEFAULT 'Propuesta',
        imagenes_json     TEXT,
        mensajes_json     TEXT,
        created_at        TEXT,
        fecha_inicio      TEXT,
        fecha_fin         TEXT,
        synced_at         TEXT,
        needs_sync        INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_segmentos_ct ON segmentos(ct_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_segmentos_sync ON segmentos(needs_sync)',
    );
  }

  Future<void> _createImagenesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS imagenes_actividad (
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
      'CREATE INDEX IF NOT EXISTS idx_imagenes_actividad '
      'ON imagenes_actividad(actividad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_imagenes_segmento '
      'ON imagenes_actividad(segmento_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_imagenes_sync '
      'ON imagenes_actividad(sync_status)',
    );
  }

  Future<void> _createGasoductosTable(Database db) async {
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
}
