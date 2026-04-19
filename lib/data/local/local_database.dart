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
      version: 8,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createSegmentosTable(db);
    await _createImagenesTable(db);
    await _createGasoductosTable(db);
    await _createPksTable(db);
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
    if (oldVersion < 6) {
      // ImagenSegmentoEntity reescrita para alinearse con el backend
      // (`ruta`, `capturada_at`, `latitud`, `subida_at`, ...). La tabla legacy
      // `imagenes_actividad` queda obsoleta — la caché local se descarta y el
      // outbox huérfano se purga. La nueva tabla añade `client_id` para que el
      // outbox sea idempotente antes de tener `id` remoto.
      await db.execute('DROP TABLE IF EXISTS imagenes_actividad');
      await db.delete(
        'sync_queue',
        where: 'entity_type = ?',
        whereArgs: ['imagen'],
      );
      await _createImagenesTable(db);
    }
    if (oldVersion < 7) {
      // CT id pasa a ser entero en todo el dominio: la tabla `gasoductos`
      // sustituye `ct TEXT` por `ct_id INTEGER`. La caché se descarta; al
      // próximo arranque online se reconstruye desde el backend.
      await db.execute('DROP TABLE IF EXISTS gasoductos');
      await _createGasoductosTable(db);
    }
    if (oldVersion < 8) {
      // Nueva caché de puntos kilométricos, alimentada por `PksService`.
      await _createPksTable(db);
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
      CREATE TABLE IF NOT EXISTS imagenes_segmento (
        client_id        TEXT PRIMARY KEY,
        id               INTEGER,
        actividad_id     INTEGER NOT NULL DEFAULT 0,
        segmento_id      INTEGER NOT NULL,
        tipo_foto        TEXT NOT NULL,
        filename         TEXT NOT NULL,
        ruta             TEXT NOT NULL,
        url              TEXT,
        mime_type        TEXT NOT NULL DEFAULT 'image/jpeg',
        tamanyo_bytes    INTEGER,
        latitud          REAL,
        longitud         REAL,
        fixed_latitud    REAL,
        fixed_longitud   REAL,
        capturada_at     TEXT NOT NULL,
        subida_at        TEXT,
        subida_por       INTEGER,
        created_at       TEXT,
        updated_at       TEXT,
        synced_at        TEXT,
        needs_sync       INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_imagenes_segmento_seg '
      'ON imagenes_segmento(segmento_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_imagenes_segmento_sync '
      'ON imagenes_segmento(needs_sync)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_imagenes_segmento_remote '
      'ON imagenes_segmento(id) WHERE id IS NOT NULL',
    );
  }

  Future<void> _createPksTable(Database db) async {
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

  Future<void> _createGasoductosTable(Database db) async {
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
  }
}
