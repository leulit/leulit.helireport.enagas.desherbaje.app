import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/core/sync/contracts/local_store.dart';
import 'package:helireport_desherbaje/core/sync/contracts/syncable.dart';
import 'package:helireport_desherbaje/core/sync/database/offline_database.dart';

// ---------------------------------------------------------------------------
// Minimal [Syncable] stub — only needed so [FakeStore] can type-check.
// ---------------------------------------------------------------------------
class _FakeEntity implements Syncable {
  @override
  String get clientId => 'fake';
  @override
  String? get remoteId => null;
  @override
  DateTime get updatedAt => DateTime.now();
  @override
  Map<String, dynamic> toJson() => {};
}

// ---------------------------------------------------------------------------
// Configurable [LocalStore] for testing.
// ---------------------------------------------------------------------------
class _FakeStore implements LocalStore<_FakeEntity> {
  _FakeStore({
    required this.entityType,
    this.schemaVersion = 1,
    this.migrateFn,
  });

  @override
  final String entityType;

  @override
  final int schemaVersion;

  /// How many times [migrate] was called.
  int migrateCallCount = 0;

  /// Optional override executed inside [migrate] — after any internal DDL.
  final Future<void> Function(DatabaseExecutor db)? migrateFn;

  @override
  Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    migrateCallCount++;
    await db.execute(
      'CREATE TABLE IF NOT EXISTS fake_$entityType '
      '(id INTEGER PRIMARY KEY, val TEXT)',
    );
    if (migrateFn != null) await migrateFn!(db);
  }

  // ── unused stubs ──────────────────────────────────────────────────────────

  @override
  Future<void> upsert(_FakeEntity entity, {DatabaseExecutor? txn}) async {}

  @override
  Future<void> delete(String clientId, {DatabaseExecutor? txn}) async {}

  @override
  Future<_FakeEntity?> findByClientId(String clientId) async => null;

  @override
  Future<_FakeEntity?> findByRemoteId(String remoteId) async => null;

  @override
  Future<List<_FakeEntity>> findAll() async => [];

  @override
  Future<List<_FakeEntity>> findWhere(String column, Object? value) async => [];

  @override
  Future<void> markSynced({
    required String clientId,
    String? remoteId,
    DatabaseExecutor? txn,
  }) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Opens a raw in-memory DB with the infra table pre-created.
Future<Database> _openRaw() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ${OfflineDatabase.entitySchemaVersionTable} (
      entity_type TEXT PRIMARY KEY,
      version     INTEGER NOT NULL
    )
  ''');
  return db;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // ── (a) first open creates table + version=1 ────────────────────────────
  group('migrateEntity — first open', () {
    test('creates entity table and records version=schemaVersion', () async {
      final db = await _openRaw();
      addTearDown(db.close);

      final store = _FakeStore(entityType: 'foo');
      await OfflineDatabase.migrateEntity(db, store);

      // version row written
      final rows = await db.query(
        OfflineDatabase.entitySchemaVersionTable,
        where: 'entity_type = ?',
        whereArgs: ['foo'],
      );
      expect(rows, hasLength(1));
      expect(rows.first['version'], equals(1));

      // table created
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='fake_foo'",
      );
      expect(tables, hasLength(1));
    });
  });

  // ── (b) idempotency — second migrate is a no-op ─────────────────────────
  group('migrateEntity — idempotency', () {
    test('second call does not invoke migrate again', () async {
      final db = await _openRaw();
      addTearDown(db.close);

      final store = _FakeStore(entityType: 'bar');

      await OfflineDatabase.migrateEntity(db, store);
      expect(store.migrateCallCount, equals(1));

      await OfflineDatabase.migrateEntity(db, store);
      expect(store.migrateCallCount, equals(1), reason: 'should be a no-op');
    });
  });

  // ── (c) atomicity — failed migrate rolls back ───────────────────────────
  group('migrateEntity — atomicity', () {
    test('rollback on error: version stays 0 and table does not exist', () async {
      final db = await _openRaw();
      addTearDown(db.close);

      final store = _FakeStore(
        entityType: 'baz',
        migrateFn: (_) async {
          throw Exception('intentional failure after CREATE TABLE');
        },
      );

      await expectLater(
        () => OfflineDatabase.migrateEntity(db, store),
        throwsA(isA<Exception>()),
      );

      // version must still be 0 (row not inserted)
      final rows = await db.query(
        OfflineDatabase.entitySchemaVersionTable,
        where: 'entity_type = ?',
        whereArgs: ['baz'],
      );
      expect(rows, isEmpty, reason: 'version row must not exist after rollback');

      // The table created during migrate must not exist either — SQLite in WAL
      // mode rolls back DDL inside a failed transaction.
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='fake_baz'",
      );
      expect(tables, isEmpty, reason: 'DDL must be rolled back');
    });
  });

  // ── (d) downgrade throws StateError ─────────────────────────────────────
  group('migrateEntity — downgrade guard', () {
    test('throws StateError when persisted version > schemaVersion', () async {
      final db = await _openRaw();
      addTearDown(db.close);

      // Write a version that is higher than what the store declares.
      await db.insert(
        OfflineDatabase.entitySchemaVersionTable,
        {'entity_type': 'qux', 'version': 99},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final store = _FakeStore(entityType: 'qux', schemaVersion: 1);

      await expectLater(
        () => OfflineDatabase.migrateEntity(db, store),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Downgrades are not supported'),
          ),
        ),
      );
    });
  });
}
