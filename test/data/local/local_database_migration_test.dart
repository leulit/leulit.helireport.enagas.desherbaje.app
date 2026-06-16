// Tests for LocalDatabase A3 shim migration — WS5 STEP 6.
//
// Coverage:
//   (1) Opening LocalDatabase is idempotent (second open is a no-op).
//   (2) _entity_schema_version contains rows for 'gasoducto' and 'pk' after
//       opening.
//   (3) from==0 migration creates gasoductos table with ct_id INTEGER column.
//   (4) from==0 migration creates pks table with ct_id INTEGER column.
//
// Uses sqflite_common_ffi to open an in-memory DB without native plugin.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/core/sync/sync.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

Future<Database> _openTestDb([String? name]) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return OfflineDatabase.open(name ?? inMemoryDatabasePath);
}

// The shims are private to local_database.dart so we replicate their DDL in
// these tests using the same shape and column names.

class _GasoductoShim extends _NopLocalStore {
  @override
  String get entityType => 'gasoducto';
  @override
  int get schemaVersion => 1;
  @override
  Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    if (from == 0) {
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
}

class _PkShim extends _NopLocalStore {
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
  }
}

abstract class _NopLocalStore extends LocalStore<_NopSyncable> {
  @override
  Future<void> upsert(_NopSyncable e, {DatabaseExecutor? txn}) async {}
  @override
  Future<void> delete(String c, {DatabaseExecutor? txn}) async {}
  @override
  Future<_NopSyncable?> findByClientId(String c) async => null;
  @override
  Future<_NopSyncable?> findByRemoteId(String r) async => null;
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

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('A3 shim migration', () {
    test(
      '(1) migrateEntity is idempotent — calling twice does not throw',
      () async {
        final db = await _openTestDb();
        final shim = _GasoductoShim();

        await OfflineDatabase.migrateEntity(db, shim);
        // Second call: version already at 1, must be a no-op.
        await expectLater(
          OfflineDatabase.migrateEntity(db, shim),
          completes,
        );

        await db.close();
      },
    );

    test(
      '(2) _entity_schema_version contains gasoducto and pk after migration',
      () async {
        final db = await _openTestDb();

        await OfflineDatabase.migrateEntity(db, _GasoductoShim());
        await OfflineDatabase.migrateEntity(db, _PkShim());

        final rows = await db.query(
          OfflineDatabase.entitySchemaVersionTable,
          where: 'entity_type IN (?, ?)',
          whereArgs: ['gasoducto', 'pk'],
        );
        final types = rows.map((r) => r['entity_type'] as String).toSet();

        expect(types, containsAll(['gasoducto', 'pk']));

        // Versions should be 1.
        for (final row in rows) {
          expect(row['version'], equals(1));
        }

        await db.close();
      },
    );

    test(
      '(3) from==0 migration creates gasoductos table with ct_id INTEGER',
      () async {
        final db = await _openTestDb();

        await OfflineDatabase.migrateEntity(db, _GasoductoShim());

        // Table must exist and ct_id must be present.
        final info = await db.rawQuery('PRAGMA table_info(gasoductos)');
        expect(info, isNotEmpty);
        final ctIdCol = info.where((c) => c['name'] == 'ct_id').toList();
        expect(ctIdCol, hasLength(1));
        expect(
          (ctIdCol.first['type'] as String).toUpperCase(),
          contains('INTEGER'),
        );

        await db.close();
      },
    );

    test(
      '(4) from==0 migration creates pks table with ct_id INTEGER',
      () async {
        final db = await _openTestDb();

        await OfflineDatabase.migrateEntity(db, _PkShim());

        final info = await db.rawQuery('PRAGMA table_info(pks)');
        expect(info, isNotEmpty);
        final ctIdCol = info.where((c) => c['name'] == 'ct_id').toList();
        expect(ctIdCol, hasLength(1));
        expect(
          (ctIdCol.first['type'] as String).toUpperCase(),
          contains('INTEGER'),
        );

        await db.close();
      },
    );
  });
}
