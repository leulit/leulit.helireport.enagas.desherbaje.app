import 'package:flutter_test/flutter_test.dart';
import 'package:leulit_flutter_actionmanager/leulit_flutter_actionmanager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/core/sync/contracts/auth_expired_exception.dart';
import 'package:helireport_desherbaje/core/sync/contracts/conflict_resolver.dart';
import 'package:helireport_desherbaje/core/sync/contracts/local_store.dart';
import 'package:helireport_desherbaje/core/sync/contracts/remote_adapter.dart';
import 'package:helireport_desherbaje/core/sync/contracts/remote_fetcher.dart';
import 'package:helireport_desherbaje/core/sync/contracts/sync_job.dart';
import 'package:helireport_desherbaje/core/sync/contracts/syncable.dart';
import 'package:helireport_desherbaje/core/sync/database/offline_database.dart';
import 'package:helireport_desherbaje/core/sync/engine/sync_engine.dart';
import 'package:helireport_desherbaje/core/sync/outbox/outbox_queue.dart';
import 'package:helireport_desherbaje/core/sync/sync_actions.dart';
import 'package:helireport_desherbaje/core/sync/type_registry.dart';

// ---------------------------------------------------------------------------
// Minimal test entity
// ---------------------------------------------------------------------------

class _TestEntity implements Syncable {
  @override
  final String clientId;
  @override
  final String? remoteId;
  @override
  final DateTime updatedAt;

  _TestEntity({
    required this.clientId,
    DateTime? updatedAt,
  })  : remoteId = null,
        updatedAt = updatedAt ?? DateTime.now();

  @override
  Map<String, dynamic> toJson() => {'clientId': clientId};
}

// ---------------------------------------------------------------------------
// Fake LocalStore — in-memory map, satisfies all LocalStore signatures
// ---------------------------------------------------------------------------

class _FakeStore extends LocalStore<_TestEntity> {
  final Map<String, _TestEntity> _data = {};
  final Set<String> syncedIds = {};

  @override
  String get entityType => 'test';

  @override
  int get schemaVersion => 1;

  @override
  Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    if (from == 0) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS test (
          client_id TEXT PRIMARY KEY,
          remote_id TEXT,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
  }

  @override
  Future<void> upsert(_TestEntity entity, {DatabaseExecutor? txn}) async {
    _data[entity.clientId] = entity;
  }

  @override
  Future<void> delete(String clientId, {DatabaseExecutor? txn}) async {
    _data.remove(clientId);
  }

  @override
  Future<_TestEntity?> findByClientId(String clientId) async =>
      _data[clientId];

  @override
  Future<List<_TestEntity>> findAll() async => _data.values.toList();

  @override
  Future<void> markSynced({
    required String clientId,
    String? remoteId,
    DatabaseExecutor? txn,
  }) async {
    syncedIds.add(clientId);
  }
}

// ---------------------------------------------------------------------------
// No-op fetcher (for read-only type registration)
// ---------------------------------------------------------------------------

class _NoopFetcher extends RemoteFetcher<_TestEntity> {
  @override
  Future<List<_TestEntity>> pullAll() async => [];
}

// ---------------------------------------------------------------------------
// Configurable fake adapter
// ---------------------------------------------------------------------------

class _FakeAdapter extends RemoteAdapter<_TestEntity> {
  final Future<SyncOutcome<_TestEntity>> Function(_TestEntity, SyncOperation)
      _fn;
  int callCount = 0;

  _FakeAdapter(this._fn);

  factory _FakeAdapter.success() =>
      _FakeAdapter((_, __) async => const SyncSuccess());

  factory _FakeAdapter.retryable() =>
      _FakeAdapter((_, __) async => SyncRetryable('network'));

  /// Throws [AuthExpiredException] on the Nth call (1-indexed); succeeds otherwise.
  factory _FakeAdapter.authOnCall(int n) {
    int calls = 0;
    return _FakeAdapter((_, __) async {
      calls++;
      if (calls == n) throw const AuthExpiredException();
      return const SyncSuccess();
    });
  }

  @override
  Future<SyncOutcome<_TestEntity>> push({
    required _TestEntity entity,
    required SyncOperation operation,
  }) async {
    callCount++;
    return _fn(entity, operation);
  }
}

// ---------------------------------------------------------------------------
// Infrastructure helpers
// ---------------------------------------------------------------------------

Future<Database> _openDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ${OfflineDatabase.syncQueueTable} (
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
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ${OfflineDatabase.syncConflictsTable} (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type  TEXT    NOT NULL,
      client_id    TEXT    NOT NULL,
      local_json   TEXT    NOT NULL,
      remote_json  TEXT    NOT NULL,
      detected_at  INTEGER NOT NULL,
      UNIQUE(entity_type, client_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ${OfflineDatabase.entitySchemaVersionTable} (
      entity_type TEXT PRIMARY KEY,
      version     INTEGER NOT NULL
    )
  ''');
  return db;
}

typedef _Fixture = ({
  Database db,
  OutboxQueue outbox,
  _FakeStore store,
  SyncEngine engine,
});

Future<_Fixture> _build({required _FakeAdapter adapter}) async {
  final db = await _openDb();
  final store = _FakeStore();
  await OfflineDatabase.migrateEntity(db, store);

  final outbox = OutboxQueue(db);
  final registry = TypeRegistry()
    ..register(
      TypeRegistration<_TestEntity>(
        entityType: 'test',
        store: store,
        conflictResolver: const ServerWinsResolver<_TestEntity>(),
        fromJson: (j) => _TestEntity(clientId: j['clientId'] as String),
        adapter: adapter,
      ),
    );
  final engine = SyncEngine(outbox: outbox, registry: registry, db: db);
  return (db: db, outbox: outbox, store: store, engine: engine);
}

Future<void> _seed(_Fixture f, String clientId) async {
  f.store._data[clientId] = _TestEntity(clientId: clientId);
  await f.outbox.enqueue(
    entityType: 'test',
    clientId: clientId,
    operation: SyncOperation.create,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  tearDown(() {
    ActionManager.clear();
  });

  // ── A: retryable terminates, job processed exactly once ───────────────────
  test('A – retryable adapter: drain terminates, adapter called once, '
      'isDraining=false', () async {
    final adapter = _FakeAdapter.retryable();
    final f = await _build(adapter: adapter);
    await _seed(f, 'c1');

    final summary = await f.engine.drain();

    expect(summary.retryable, equals(1));
    expect(summary.succeeded, equals(0));
    expect(adapter.callCount, equals(1));
    expect(f.engine.isDraining, isFalse);
    await f.db.close();
  });

  // ── B: second drain() re-enters cleanly (no brick) ────────────────────────
  test('B – second drain() enters after first completes (isDraining not stuck)',
      () async {
    final adapter = _FakeAdapter.success();
    final f = await _build(adapter: adapter);
    await _seed(f, 'c1');

    final first = await f.engine.drain();
    expect(first.succeeded, equals(1));
    expect(f.engine.isDraining, isFalse);

    await _seed(f, 'c2');
    final second = await f.engine.drain();
    expect(second.succeeded, equals(1));
    expect(f.engine.isDraining, isFalse);
    await f.db.close();
  });

  // ── C: 150 jobs, limit 100 — all processed, none duplicated ───────────────
  test('C – 150 jobs succeed; 2-batch walk; adapter called 150 times; '
      'outbox cleared', () async {
    final adapter = _FakeAdapter.success();
    final f = await _build(adapter: adapter);

    for (var i = 0; i < 150; i++) {
      await _seed(f, 'c$i');
    }

    final summary = await f.engine.drain();

    expect(summary.succeeded, equals(150));
    expect(summary.retryable, equals(0));
    expect(adapter.callCount, equals(150));
    expect(await f.outbox.countPending(), equals(0));
    await f.db.close();
  });

  // ── D: mixed outcomes, each adapter call exactly once ─────────────────────
  test('D – success/retryable/unrecoverable: summary correct, '
      'each job processed once', () async {
    final outcomes = <String, SyncOutcome<_TestEntity>>{
      'ok': const SyncSuccess(),
      'ret': SyncRetryable('net'),
      'bad': const SyncUnrecoverable('nope'),
    };
    final callsPerClient = <String, int>{};
    final adapter = _FakeAdapter((entity, _) async {
      callsPerClient[entity.clientId] =
          (callsPerClient[entity.clientId] ?? 0) + 1;
      return outcomes[entity.clientId]!;
    });

    final f = await _build(adapter: adapter);
    for (final id in ['ok', 'ret', 'bad']) {
      await _seed(f, id);
    }

    final summary = await f.engine.drain();

    expect(summary.succeeded, equals(1));
    expect(summary.retryable, equals(1));
    expect(summary.rejected, equals(1));
    expect(summary.authExpired, isFalse);
    for (final id in ['ok', 'ret', 'bad']) {
      expect(callsPerClient[id], equals(1),
          reason: 'adapter called >1 times for $id');
    }
    await f.db.close();
  });

  // ── E: AuthExpiredException on 2nd of 3 jobs ──────────────────────────────
  test('E – auth expires on 2nd job: authExpired=true, isDraining=false, '
      'SyncActions.authExpired dispatched once, c2 back to pending', () async {
    final adapter = _FakeAdapter.authOnCall(2); // c1 succeeds, c2 throws
    final f = await _build(adapter: adapter);
    for (final id in ['c1', 'c2', 'c3']) {
      await _seed(f, id);
    }

    int authExpiredCount = 0;
    SyncActions.authExpired.on((_) => authExpiredCount++);

    final summary = await f.engine.drain();

    // dispatch() is sync but handlers run in a microtask — flush before asserting
    await Future.microtask(() {});

    expect(summary.authExpired, isTrue);
    expect(f.engine.isDraining, isFalse);
    expect(authExpiredCount, equals(1));

    // c2 must be back to pending (not stuck in syncing)
    final pending = await f.outbox.pendingJobs();
    final c2 = pending.where((j) => j.clientId == 'c2').toList();
    expect(c2, hasLength(1));
    expect(c2.first.status, equals(SyncStatus.pending));

    await f.db.close();
  });

  // ── F: read-only entity (no adapter) → markRejected, rejected:1 ──────────
  test('F – read-only entity: markRejected called, rejected:1', () async {
    final db = await _openDb();
    final store = _FakeStore();
    await OfflineDatabase.migrateEntity(db, store);

    final outbox = OutboxQueue(db);
    final registry = TypeRegistry()
      ..register(
        TypeRegistration<_TestEntity>(
          entityType: 'test',
          store: store,
          conflictResolver: const ServerWinsResolver<_TestEntity>(),
          fromJson: (j) => _TestEntity(clientId: j['clientId'] as String),
          fetcher: _NoopFetcher(), // adapter is null → read-only
        ),
      );
    final engine = SyncEngine(outbox: outbox, registry: registry, db: db);

    store._data['r1'] = _TestEntity(clientId: 'r1');
    await outbox.enqueue(
      entityType: 'test',
      clientId: 'r1',
      operation: SyncOperation.create,
    );

    final summary = await engine.drain();

    expect(summary.rejected, equals(1));
    expect(summary.succeeded, equals(0));
    final rejected = await outbox.rejectedJobs();
    expect(rejected, hasLength(1));
    expect(rejected.first.clientId, equals('r1'));
    await db.close();
  });

  // ── G: pipeline disposed exactly once — drain completes normally ───────────
  // Indirect: if dispose() were called per-job (old behaviour), the second
  // job would throw "Cannot run a disposed pipeline". 10 jobs running in one
  // drain proves the hoisted pipeline is reused correctly.
  test('G – hoisted pipeline not disposed mid-run; 10 jobs succeed', () async {
    final adapter = _FakeAdapter.success();
    final f = await _build(adapter: adapter);
    for (var i = 0; i < 10; i++) {
      await _seed(f, 'g$i');
    }

    final summary = await f.engine.drain();
    expect(summary.succeeded, equals(10));
    expect(f.engine.isDraining, isFalse);
    await f.db.close();
  });

  // Pipeline is disposed on auth early-return too (new drain works after).
  test('G-auth – pipeline disposed on auth abort; next drain enters cleanly',
      () async {
    final adapter = _FakeAdapter.authOnCall(1);
    final f = await _build(adapter: adapter);
    await _seed(f, 'x');
    SyncActions.authExpired.on((_) {}); // absorb

    final s1 = await f.engine.drain();
    expect(s1.authExpired, isTrue);
    expect(f.engine.isDraining, isFalse);

    // A fresh drain using the same engine must start cleanly.
    // The x job is pending again; adapter call 2 succeeds (authOnCall n=1 only throws once).
    final s2 = await f.engine.drain();
    // The job is retried; call 2 is success.
    expect(s2.succeeded, equals(1));
    expect(f.engine.isDraining, isFalse);
    await f.db.close();
  });
}
