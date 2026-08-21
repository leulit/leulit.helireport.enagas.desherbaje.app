import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../core/sync/sync.dart';

// A3 ship-blocker-later ──────────────────────────────────────────────────────
// Shim LocalStore-shaped objects that participate in the versioned migration
// system for `gasoductos` and `pks`. They do NOT route read/write traffic —
// GasoductosService and PksService still use raw SQL. The sole purpose is to
// register the schema in `_entity_schema_version` so future migrations can
// evolve the table via the standard `OfflineDatabase.migrateEntity` path.
//
// TODO A3 ship-blocker-later: replace with full LocalStore<GasoductoEntity>
//   and LocalStore<PkEntity> when GasoductosService / PksService are migrated
//   to the offline motor (requires REST endpoints from the backend — §12.2).

class _GasoductoSchemaShim extends _NopLocalStore {
  @override
  String get entityType => 'gasoducto';

  @override
  int get schemaVersion => 1;

  @override
  Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    if (from == 0) {
      // Los builds anteriores al motor offline crearon `gasoductos` con
      // `ct TEXT`. En esos dispositivos la tabla YA existe, así que el
      // `CREATE TABLE IF NOT EXISTS` de abajo no hace nada y la versión sube
      // igualmente a 1: el insert del sync muere con "no column named ct_id"
      // para siempre. Es caché de master data (se vuelve a descargar), así que
      // la vía barata es tirarla y recrearla.
      await dropIfLacksColumn(db, 'gasoductos', 'ct_id');
      // CREATE verbatim — includes ct_id INTEGER as established by the 2026
      // schema migration that converted the legacy ct TEXT column.
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
    // Future schema bumps go here (from == 1 → 2, etc.).
  }
}

class _PkSchemaShim extends _NopLocalStore {
  @override
  String get entityType => 'pk';

  @override
  int get schemaVersion => 1;

  @override
  Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    if (from == 0) {
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
    // Future schema bumps go here.
  }
}

class _HitoSchemaShim extends _NopLocalStore {
  @override
  String get entityType => 'hito';

  @override
  int get schemaVersion => 1;

  @override
  Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    if (from == 0) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS hitos (
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
        'CREATE INDEX IF NOT EXISTS idx_hitos_ct ON hitos(ct_id)',
      );
    }
    // Future schema bumps go here.
  }
}

/// Tira [table] si existe con un esquema viejo que no tiene [column].
/// Solo para tablas de caché re-descargable (master data).
@visibleForTesting
Future<void> dropIfLacksColumn(
  DatabaseExecutor db,
  String table,
  String column,
) async {
  final cols = await db.rawQuery('PRAGMA table_info($table)');
  if (cols.isNotEmpty && !cols.any((c) => c['name'] == column)) {
    await db.execute('DROP TABLE $table');
  }
}

/// Abstract NOP base so the shims only need to override the schema methods.
abstract class _NopLocalStore extends LocalStore<_NopSyncable> {
  @override
  Future<void> upsert(_NopSyncable entity, {DatabaseExecutor? txn}) async {}

  @override
  Future<void> delete(String clientId, {DatabaseExecutor? txn}) async {}

  @override
  Future<_NopSyncable?> findByClientId(String clientId) async => null;

  @override
  Future<_NopSyncable?> findByRemoteId(String remoteId) async => null;

  @override
  Future<List<_NopSyncable>> findAll() async => const [];

  @override
  Future<List<_NopSyncable>> findWhere(String column, Object? value) async =>
      const [];

  @override
  Future<void> markSynced({
    required String clientId,
    String? remoteId,
    DatabaseExecutor? txn,
  }) async {}
}

/// Placeholder Syncable used only by the NOP shims above.
class _NopSyncable implements Syncable {
  @override
  String get clientId => '';
  @override
  String? get remoteId => null;
  @override
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(0);
  @override
  Map<String, dynamic> toJson() => const {};
}

// ─────────────────────────────────────────────────────────────────────────────

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
    // A3 ship-blocker-later: register gasoductos/pks schema via the versioned
    // migration system so future schema changes have a safe upgrade path.
    await OfflineDatabase.migrateEntity(db, _GasoductoSchemaShim());
    await OfflineDatabase.migrateEntity(db, _PkSchemaShim());
    await OfflineDatabase.migrateEntity(db, _HitoSchemaShim());
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
}
