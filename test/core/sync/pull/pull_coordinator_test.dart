// Tests for PullCoordinator — NF-1, NF-2, NF-3, NF-5, NF-6 (WS4).
//
// Strategy: real in-memory SQLite via sqflite_common_ffi so the infra tables
// exist and UpdatePullStateTask / EnqueueConflictsTask operate on real SQL.
// RemoteFetcher and LocalStore are mocked via mocktail to control outcomes.
// DetectConflictsTask needs a real OutboxQueue (uses DB) — provided, clean.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/core/sync/contracts/auth_expired_exception.dart';
import 'package:helireport_desherbaje/core/sync/contracts/conflict_resolver.dart';
import 'package:helireport_desherbaje/core/sync/contracts/local_store.dart';
import 'package:helireport_desherbaje/core/sync/contracts/remote_fetcher.dart';
import 'package:helireport_desherbaje/core/sync/contracts/sync_job.dart';
import 'package:helireport_desherbaje/core/sync/database/offline_database.dart';
import 'package:helireport_desherbaje/core/sync/outbox/outbox_queue.dart';
import 'package:helireport_desherbaje/core/sync/pull/pull_coordinator.dart';
import 'package:helireport_desherbaje/core/sync/pull/pull_outcome.dart';
import 'package:helireport_desherbaje/core/sync/sync_actions.dart';
import 'package:helireport_desherbaje/core/sync/type_registry.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class MockLocalStore extends Mock implements LocalStore<SegmentoEntity> {}

class MockRemoteFetcher extends Mock implements RemoteFetcher<SegmentoEntity> {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

SegmentoEntity _seg({
  required String clientId,
  int? id,
  DateTime? updatedAt,
}) {
  final ts = (updatedAt ?? DateTime(2025)).toIso8601String();
  return SegmentoEntity.fromJson({
    'client_id': clientId,
    'id': id,
    'ct_id': 1,
    'tipo_instalacion': 'lineal',
    'tipo_actividad': 'deshierbe_selectivo',
    'estado': 'propuesta',
    'descripcion': '',
    'updated_at': ts,
  });
}

/// Opens an in-memory SQLite database with the same infra tables as
/// [OfflineDatabase.open], without the WAL rawQuery (not needed in-memory).
Future<Database> _openTestDb() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ${OfflineDatabase.entitySchemaVersionTable} (
      entity_type TEXT PRIMARY KEY,
      version     INTEGER NOT NULL
    )
  ''');
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
    CREATE TABLE IF NOT EXISTS ${OfflineDatabase.pullStateTable} (
      entity_type    TEXT    PRIMARY KEY,
      last_pulled_at INTEGER,
      last_status    TEXT,
      last_error     TEXT
    )
  ''');
  return db;
}

TypeRegistration<SegmentoEntity> _reg(
  MockLocalStore store,
  MockRemoteFetcher fetcher,
) =>
    TypeRegistration<SegmentoEntity>(
      entityType: 'segmento',
      store: store,
      fetcher: fetcher,
      conflictResolver: const ServerWinsResolver<SegmentoEntity>(),
      fromJson: SegmentoEntity.fromJson,
    );

Future<Map<String, dynamic>?> _readPullState(Database db) async {
  final rows = await db.query(
    OfflineDatabase.pullStateTable,
    where: 'entity_type = ?',
    whereArgs: ['segmento'],
  );
  return rows.isEmpty ? null : rows.first;
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late Database db;
  late OutboxQueue outbox;
  late MockLocalStore mockStore;
  late MockRemoteFetcher mockFetcher;
  late PullCoordinator<SegmentoEntity> coordinator;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    registerFallbackValue(SegmentoEntity.empty());
  });

  setUp(() async {
    db = await _openTestDb();
    outbox = OutboxQueue(db);
    mockStore = MockLocalStore();
    mockFetcher = MockRemoteFetcher();

    // Default store stubs — no existing local rows.
    when(() => mockStore.findByClientId(any()))
        .thenAnswer((_) async => null);
    when(() => mockStore.findByRemoteId(any()))
        .thenAnswer((_) async => null);
    when(() => mockStore.upsert(any())).thenAnswer((_) async {});
    when(() => mockStore.markSynced(
          clientId: any(named: 'clientId'),
          remoteId: any(named: 'remoteId'),
        )).thenAnswer((_) async {});
    when(() => mockStore.entityType).thenReturn('segmento');

    coordinator = PullCoordinator<SegmentoEntity>(
      registration: _reg(mockStore, mockFetcher),
      outbox: outbox,
      db: db,
    );
  });

  tearDown(() async {
    await db.close();
  });

  // ─── NF-1: non-auth blocking failure ────────────────────────────────────────
  group('NF-1 — non-auth blocking failure', () {
    test('outcome==error, errorMessage contains exception text, isDegraded',
        () async {
      when(() => mockFetcher.pullAll()).thenThrow(Exception('boom'));

      final summary = await coordinator.pullNow();

      expect(summary.outcome, PullOutcome.error);
      expect(summary.errorMessage, contains('boom'));
      expect(summary.isDegraded, isTrue);
    });

    test('pull_state.last_status == error, last_error is set', () async {
      when(() => mockFetcher.pullAll()).thenThrow(Exception('server down'));

      await coordinator.pullNow();

      final state = await _readPullState(db);
      expect(state, isNotNull);
      expect(state!['last_status'], equals('error'));
      expect(state['last_error'], contains('server down'));
    });
  });

  // ─── NF-1 auth: AuthExpiredException ────────────────────────────────────────
  group('NF-1 auth — AuthExpiredException', () {
    test('outcome==authExpired, pull_state==auth_expired', () async {
      when(() => mockFetcher.pullAll())
          .thenThrow(const AuthExpiredException('token invalid'));

      final summary = await coordinator.pullNow();

      expect(summary.outcome, PullOutcome.authExpired);
      expect(summary.authExpired, isTrue);

      final state = await _readPullState(db);
      expect(state!['last_status'], equals('auth_expired'));
    });

    test('SyncActions.authExpired dispatched exactly once', () async {
      when(() => mockFetcher.pullAll())
          .thenThrow(const AuthExpiredException());

      int dispatches = 0;
      final handlerId = SyncActions.authExpired.on(
        (_) => dispatches++,
        debugLabel: 'test_auth_expired',
      );
      try {
        await coordinator.pullNow();
      } finally {
        SyncActions.authExpired.off(handlerId);
      }

      expect(dispatches, equals(1));
    });
  });

  // ─── NF-2: partial upsert failure ───────────────────────────────────────────
  group('NF-2 — partial upsert failure (2nd of 3 items fails)', () {
    setUp(() {
      final remoteItems = [
        _seg(clientId: 'cid-1', id: 1),
        _seg(clientId: 'cid-2', id: 2),
        _seg(clientId: 'cid-3', id: 3),
      ];
      when(() => mockFetcher.pullAll()).thenAnswer((_) async => remoteItems);

      int call = 0;
      when(() => mockStore.upsert(any())).thenAnswer((_) async {
        call++;
        if (call == 2) throw Exception('disk full');
      });
    });

    test('outcome==partial, upserted==2, isDegraded', () async {
      final summary = await coordinator.pullNow();

      expect(summary.outcome, PullOutcome.partial);
      expect(summary.upserted, equals(2));
      expect(summary.isDegraded, isTrue);
    });

    test('pull_state.last_status==partial', () async {
      await coordinator.pullNow();

      final state = await _readPullState(db);
      expect(state!['last_status'], equals('partial'));
    });
  });

  // ─── NF-3: enqueue_conflicts DB failure ─────────────────────────────────────
  group('NF-3 — conflict DB insert fails', () {
    test('outcome==partial, partialErrors from EnqueueConflicts', () async {
      // Make a remote item that will be detected as a conflict by having
      // an outbox pending job for it.
      final localSeg = _seg(
        clientId: 'c-conflict',
        id: 42,
        updatedAt: DateTime(2025, 1, 1),
      );
      final remoteSeg = _seg(
        clientId: 'c-conflict',
        id: 42,
        updatedAt: DateTime(2025, 12, 31),
      );
      when(() => mockFetcher.pullAll())
          .thenAnswer((_) async => [remoteSeg]);
      when(() => mockStore.findByRemoteId('42'))
          .thenAnswer((_) async => localSeg);
      when(() => mockStore.findByClientId('c-conflict'))
          .thenAnswer((_) async => localSeg);

      // Create an outbox pending job so DetectConflictsTask marks it as conflict.
      await outbox.enqueue(
        entityType: 'segmento',
        clientId: 'c-conflict',
        operation: SyncOperation.update,
      );

      // Break the sync_conflicts table so the DB insert fails.
      await db.execute(
          'DROP TABLE IF EXISTS ${OfflineDatabase.syncConflictsTable}');

      final summary = await coordinator.pullNow();

      expect(summary.outcome, PullOutcome.partial);
      expect(summary.isDegraded, isTrue);
    });
  });

  // ─── NF-5: ok vs okWithConflicts in pull_state ──────────────────────────────
  group('NF-5 — pull_state reflects outcome', () {
    test('no conflicts → outcome==ok, last_error==null', () async {
      when(() => mockFetcher.pullAll())
          .thenAnswer((_) async => [_seg(clientId: 'cid-a', id: 1)]);

      final summary = await coordinator.pullNow();

      expect(summary.outcome, PullOutcome.ok);
      expect(summary.errorMessage, isNull);

      final state = await _readPullState(db);
      expect(state!['last_status'], equals('ok'));
      expect(state['last_error'], isNull);
    });

    test('with conflicts → outcome==okWithConflicts, last_error==null', () async {
      final localSeg =
          _seg(clientId: 'c1', id: 10, updatedAt: DateTime(2025, 1, 1));
      final remoteSeg =
          _seg(clientId: 'c1', id: 10, updatedAt: DateTime(2025, 12, 31));
      when(() => mockFetcher.pullAll())
          .thenAnswer((_) async => [remoteSeg]);
      when(() => mockStore.findByRemoteId('10'))
          .thenAnswer((_) async => localSeg);
      when(() => mockStore.findByClientId('c1'))
          .thenAnswer((_) async => localSeg);

      // Pending job → DetectConflictsTask classifies as conflict.
      await outbox.enqueue(
        entityType: 'segmento',
        clientId: 'c1',
        operation: SyncOperation.update,
      );

      final summary = await coordinator.pullNow();

      expect(summary.outcome, PullOutcome.okWithConflicts);
      expect(summary.errorMessage, isNull);

      final state = await _readPullState(db);
      expect(state!['last_status'], equals('ok_with_conflicts'));
      expect(state['last_error'], isNull);
    });
  });

  // ─── NF-6: cloudPullCompleted dispatch policy ────────────────────────────────
  group('NF-6 — cloudPullCompleted dispatch policy', () {
    test('blocking failure → cloudPullCompleted is NEVER dispatched', () async {
      when(() => mockFetcher.pullAll()).thenThrow(Exception('network error'));

      int dispatches = 0;
      final handlerId = SyncActions.cloudPullCompleted.on(
        (_) => dispatches++,
        debugLabel: 'test_nf6_blocking',
      );
      try {
        await coordinator.pullNow();
      } finally {
        SyncActions.cloudPullCompleted.off(handlerId);
      }

      expect(dispatches, equals(0));
    });

    test('partial outcome → cloudPullCompleted IS dispatched with outcome==partial',
        () async {
      when(() => mockFetcher.pullAll())
          .thenAnswer((_) async => [_seg(clientId: 'p1', id: 1)]);

      int call = 0;
      when(() => mockStore.upsert(any())).thenAnswer((_) async {
        call++;
        if (call == 1) throw Exception('io error');
      });

      CloudPullCompletedEvent? captured;
      final handlerId = SyncActions.cloudPullCompleted.on(
        (event) => captured = event.data,
        debugLabel: 'test_nf6_partial',
      );
      try {
        await coordinator.pullNow();
      } finally {
        SyncActions.cloudPullCompleted.off(handlerId);
      }

      expect(captured, isNotNull);
      expect(captured!.outcome, PullOutcome.partial);
    });
  });
}
