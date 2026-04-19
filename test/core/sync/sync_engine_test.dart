import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:helireport_desherbaje/core/sync/sync.dart';
import 'package:leulit_flutter_actionmanager/leulit_flutter_actionmanager.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeSyncable implements Syncable {
  @override
  final String clientId;
  @override
  final String? remoteId;
  @override
  final DateTime updatedAt;
  final String name;

  FakeSyncable({
    required this.clientId,
    this.remoteId,
    DateTime? updatedAt,
    this.name = 'fake',
  }) : updatedAt = updatedAt ?? DateTime(2025, 1, 1);

  @override
  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'remoteId': remoteId,
        'updatedAt': updatedAt.toIso8601String(),
        'name': name,
      };

  factory FakeSyncable.fromJson(Map<String, dynamic> json) => FakeSyncable(
        clientId: json['clientId'] as String,
        remoteId: json['remoteId'] as String?,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        name: (json['name'] as String?) ?? 'fake',
      );

  @override
  bool operator ==(Object other) =>
      other is FakeSyncable && other.clientId == clientId;

  @override
  int get hashCode => clientId.hashCode;
}

class FakeLocalStore extends LocalStore<FakeSyncable> {
  final List<FakeSyncable> upsertCalls = [];
  final List<String> deleteCalls = [];
  final List<({String clientId, String? remoteId})> markSyncedCalls = [];

  @override
  Future<void> upsert(FakeSyncable entity, {DatabaseExecutor? txn}) async {
    upsertCalls.add(entity);
  }

  @override
  Future<void> delete(String clientId, {DatabaseExecutor? txn}) async {
    deleteCalls.add(clientId);
  }

  @override
  Future<FakeSyncable?> findByClientId(String clientId) async => null;

  @override
  Future<List<FakeSyncable>> findAll() async => const [];

  @override
  Future<void> markSynced({
    required String clientId,
    String? remoteId,
    DatabaseExecutor? txn,
  }) async {
    markSyncedCalls.add((clientId: clientId, remoteId: remoteId));
  }
}

class FakeRemoteAdapter extends RemoteAdapter<FakeSyncable> {
  final List<SyncOutcome<FakeSyncable>> outcomes = [];
  final List<({FakeSyncable entity, SyncOperation operation})> invocations = [];

  /// Optional hook executed *before* returning the queued outcome.
  /// Used in the mid-drain connectivity-loss test.
  void Function(int callIndex)? onPush;

  @override
  Future<SyncOutcome<FakeSyncable>> push({
    required FakeSyncable entity,
    required SyncOperation operation,
  }) async {
    final idx = invocations.length;
    invocations.add((entity: entity, operation: operation));
    onPush?.call(idx);
    if (outcomes.isEmpty) {
      return SyncRetryable<FakeSyncable>('no outcome queued');
    }
    return outcomes.removeAt(0);
  }
}

class FakeConflictResolver extends ConflictResolver<FakeSyncable> {
  @override
  ResolutionResult<FakeSyncable> resolve({
    required FakeSyncable local,
    required FakeSyncable server,
  }) =>
      ResolutionResult.keepLocal(local);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _entityType = 'fake';

Future<int> _enqueueJob({
  required OutboxQueue outbox,
  required String clientId,
  SyncOperation operation = SyncOperation.create,
  String entityType = _entityType,
}) {
  final payload = jsonEncode(FakeSyncable(clientId: clientId).toJson());
  return outbox.enqueue(
    entityType: entityType,
    entityId: clientId,
    operation: operation,
    payload: payload,
  );
}

/// Pumps pending microtasks so dispatched `SyncActions` events are delivered
/// to the registered handlers before assertions run.
Future<void> _pumpMicrotasks() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late OutboxQueue outbox;
  late TypeRegistry registry;
  late FakeRemoteAdapter adapter;
  late FakeLocalStore localStore;
  late SyncEngine engine;
  late bool isOnline;

  // Handler IDs so we can cleanly unregister in tearDown.
  final handlerIds = <(TypedAction, String)>[];

  String listen<T>(TypedAction<T> action, void Function(ActionEvent<T>) h) {
    final id = action.on(h);
    handlerIds.add((action, id));
    return id;
  }

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, _) => OutboxSchema.ensure(d),
      ),
    );
    outbox = OutboxQueue(db);
    registry = TypeRegistry();
    adapter = FakeRemoteAdapter();
    localStore = FakeLocalStore();
    registry.register<FakeSyncable>(
      TypeRegistration<FakeSyncable>(
        entityType: _entityType,
        adapter: adapter,
        conflictResolver: FakeConflictResolver(),
        fromJson: FakeSyncable.fromJson,
        localStore: localStore,
      ),
    );
    isOnline = true;
    engine = SyncEngine(
      outbox: outbox,
      registry: registry,
      isOnline: () => isOnline,
    );
  });

  tearDown(() async {
    for (final (action, id) in handlerIds) {
      action.off(id);
    }
    handlerIds.clear();
    await outbox.dispose();
    await db.close();
  });

  // -------------------------------------------------------------------------
  group('SyncEngine outcome handling', () {
    test('SyncSuccess on create marks job synced and dispatches entitySynced',
        () async {
      adapter.outcomes.add(const SyncSuccess<FakeSyncable>(remoteId: 'r-1'));
      final jobId = await _enqueueJob(outbox: outbox, clientId: 'c-1');

      final syncedEvents = <EntitySyncedEvent>[];
      listen<EntitySyncedEvent>(
        SyncActions.entitySynced,
        (e) => syncedEvents.add(e.data!),
      );

      final result = await engine.drain();
      await _pumpMicrotasks();

      final job = (await outbox.byId(jobId))!;
      expect(job.status, SyncStatus.synced);
      expect(job.remoteId, 'r-1');

      expect(localStore.markSyncedCalls, hasLength(1));
      expect(localStore.markSyncedCalls.single.clientId, 'c-1');
      expect(localStore.markSyncedCalls.single.remoteId, 'r-1');
      expect(localStore.deleteCalls, isEmpty);

      expect(syncedEvents, hasLength(1));
      expect(syncedEvents.single.entityType, _entityType);
      expect(syncedEvents.single.entityId, 'c-1');
      expect(syncedEvents.single.remoteId, 'r-1');

      expect(result, isNotNull);
      expect(result!.processed, 1);
      expect(result.failed, 0);
    });

    test('SyncSuccess on delete calls LocalStore.delete, not markSynced',
        () async {
      adapter.outcomes.add(const SyncSuccess<FakeSyncable>(remoteId: 'r-1'));
      final jobId = await _enqueueJob(
        outbox: outbox,
        clientId: 'c-del',
        operation: SyncOperation.delete,
      );

      await engine.drain();
      await _pumpMicrotasks();

      final job = (await outbox.byId(jobId))!;
      expect(job.status, SyncStatus.synced);

      expect(localStore.deleteCalls, equals(['c-del']));
      expect(localStore.markSyncedCalls, isEmpty);
    });

    test('SyncRetryable returns job to pending and increments attempts',
        () async {
      // Note: the engine's outer `while (_isOnline())` loop keeps re-draining
      // the queue until empty, so a retryable job would be re-processed
      // repeatedly until maxAttempts. To observe the single-retry state we
      // force the engine to exit after exactly one push by flipping isOnline
      // in the adapter's onPush hook.
      adapter.outcomes.add(const SyncRetryable<FakeSyncable>('502 bad gateway'));
      adapter.onPush = (idx) {
        if (idx == 0) isOnline = false;
      };
      final jobId = await _enqueueJob(outbox: outbox, clientId: 'c-r');

      var syncedDispatched = 0;
      listen<EntitySyncedEvent>(
        SyncActions.entitySynced,
        (_) => syncedDispatched++,
      );
      final failedEvents = <EntityFailedEvent>[];
      listen<EntityFailedEvent>(
        SyncActions.entityFailed,
        (e) => failedEvents.add(e.data!),
      );

      await engine.drain();
      await _pumpMicrotasks();

      final job = (await outbox.byId(jobId))!;
      expect(job.status, SyncStatus.pending);
      expect(job.attempts, 1);
      expect(job.lastError, '502 bad gateway');
      expect(adapter.invocations, hasLength(1));

      expect(localStore.markSyncedCalls, isEmpty);
      expect(syncedDispatched, 0);

      expect(failedEvents, hasLength(1));
      expect(failedEvents.single.retryable, isTrue);
      expect(failedEvents.single.error, '502 bad gateway');
    });

    test('SyncUnrecoverable marks job dead and dispatches entityFailed',
        () async {
      adapter.outcomes.add(
        const SyncUnrecoverable<FakeSyncable>('422 validation', statusCode: 422),
      );
      final jobId = await _enqueueJob(outbox: outbox, clientId: 'c-u');

      final failedEvents = <EntityFailedEvent>[];
      listen<EntityFailedEvent>(
        SyncActions.entityFailed,
        (e) => failedEvents.add(e.data!),
      );

      await engine.drain();
      await _pumpMicrotasks();

      final job = (await outbox.byId(jobId))!;
      expect(job.status, SyncStatus.dead);
      expect(job.lastError, '422 validation');

      expect(failedEvents, hasLength(1));
      expect(failedEvents.single.retryable, isFalse);
      expect(failedEvents.single.error, '422 validation');
      expect(localStore.markSyncedCalls, isEmpty);
    });

    test('SyncConflict marks job dead and dispatches entityConflict',
        () async {
      final server = FakeSyncable(clientId: 'c-c', remoteId: 'r-c');
      adapter.outcomes.add(SyncConflict<FakeSyncable>(server));
      final jobId = await _enqueueJob(outbox: outbox, clientId: 'c-c');

      final conflictEvents = <EntityConflictEvent>[];
      listen<EntityConflictEvent>(
        SyncActions.entityConflict,
        (e) => conflictEvents.add(e.data!),
      );

      await engine.drain();
      await _pumpMicrotasks();

      final job = (await outbox.byId(jobId))!;
      expect(job.status, SyncStatus.dead);
      expect(job.lastError, 'Conflict');

      expect(conflictEvents, hasLength(1));
      expect(conflictEvents.single.entityType, _entityType);
      expect(conflictEvents.single.entityId, 'c-c');
    });
  });

  // -------------------------------------------------------------------------
  group('SyncEngine retry limits', () {
    test('reaches maxAttempts and promotes job to dead (default 5)', () async {
      // Default maxAttempts = 5. markSyncing increments attempts before each
      // adapter call; the engine's outer loop keeps retrying a pending job
      // until it is either synced or dead-lettered. A single drain() call is
      // enough: attempts go 1, 2, 3, 4, 5; on the 5th retryable outcome
      // _handleRetryable sees attempts >= maxAttempts and marks dead.
      for (var i = 0; i < 5; i++) {
        adapter.outcomes.add(SyncRetryable<FakeSyncable>('retry $i'));
      }
      final jobId = await _enqueueJob(outbox: outbox, clientId: 'c-max');

      await engine.drain();
      await _pumpMicrotasks();

      final job = (await outbox.byId(jobId))!;
      expect(job.status, SyncStatus.dead);
      expect(job.attempts, 5);
      expect(job.lastError, contains('Max attempts reached'));
      expect(adapter.invocations, hasLength(5));
    });
  });

  // -------------------------------------------------------------------------
  group('SyncEngine connectivity gating', () {
    test('offline: drain is a no-op, adapter never invoked', () async {
      isOnline = false;
      await _enqueueJob(outbox: outbox, clientId: 'c-off');

      final result = await engine.drain();

      expect(result, isNull);
      expect(adapter.invocations, isEmpty);
      expect(
        (await outbox.nextPending()).single.status,
        SyncStatus.pending,
      );
    });

    test('mid-drain connectivity loss stops after in-flight job', () async {
      // Three pending jobs; connectivity drops during the first push but the
      // first outcome is still returned, so job #1 syncs and #2/#3 stay pending.
      adapter.outcomes
        ..add(const SyncSuccess<FakeSyncable>(remoteId: 'r-1'))
        ..add(const SyncSuccess<FakeSyncable>(remoteId: 'r-2'))
        ..add(const SyncSuccess<FakeSyncable>(remoteId: 'r-3'));

      adapter.onPush = (idx) {
        if (idx == 0) isOnline = false;
      };

      final j1 = await _enqueueJob(outbox: outbox, clientId: 'c-1');
      final j2 = await _enqueueJob(outbox: outbox, clientId: 'c-2');
      final j3 = await _enqueueJob(outbox: outbox, clientId: 'c-3');

      await engine.drain();
      await _pumpMicrotasks();

      expect(adapter.invocations, hasLength(1));
      expect((await outbox.byId(j1))!.status, SyncStatus.synced);
      expect((await outbox.byId(j2))!.status, SyncStatus.pending);
      expect((await outbox.byId(j3))!.status, SyncStatus.pending);
    });
  });

  // -------------------------------------------------------------------------
  group('SyncEngine batch sizing', () {
    test('batch size 5: enqueue 8, drain with forced break after batch, '
        '5 processed / 3 pending', () async {
      // The engine's outer `while (_isOnline())` loop keeps pulling new
      // batches until the queue is empty, so to observe a single batch we
      // flip isOnline AFTER the 5th successful push. This mirrors real-world
      // "connectivity held long enough for one batch" semantics.
      for (var i = 0; i < 5; i++) {
        adapter.outcomes.add(SyncSuccess<FakeSyncable>(remoteId: 'r-$i'));
      }
      adapter.onPush = (idx) {
        // Flip offline the moment the 5th push begins so that when the inner
        // for-loop checks `if (!_isOnline()) break;` at the top of iteration 6
        // — and the outer while — both short-circuit.
        if (idx == 4) isOnline = false;
      };

      final ids = <int>[];
      for (var i = 0; i < 8; i++) {
        ids.add(await _enqueueJob(outbox: outbox, clientId: 'c-$i'));
      }

      await engine.drain();
      await _pumpMicrotasks();

      // Exactly 5 adapter calls — the configured batch size.
      expect(adapter.invocations, hasLength(5));
      expect(const SyncEngineConfig().batchSize, 5);

      final syncedCount = await outbox.countByStatus(SyncStatus.synced);
      final pendingCount =
          await outbox.countByStatus(SyncStatus.pending);
      expect(syncedCount, 5);
      expect(pendingCount, 3);

      // Spot-check: first 5 ids are synced, last 3 are pending.
      for (var i = 0; i < 5; i++) {
        expect((await outbox.byId(ids[i]))!.status, SyncStatus.synced);
      }
      for (var i = 5; i < 8; i++) {
        expect((await outbox.byId(ids[i]))!.status, SyncStatus.pending);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('SyncEngine unregistered entity type', () {
    test('marks job dead and dispatches retryable=false failure', () async {
      final jobId = await _enqueueJob(
        outbox: outbox,
        clientId: 'c-unk',
        entityType: 'not-registered',
      );

      final failedEvents = <EntityFailedEvent>[];
      listen<EntityFailedEvent>(
        SyncActions.entityFailed,
        (e) => failedEvents.add(e.data!),
      );

      await engine.drain();
      await _pumpMicrotasks();

      expect(adapter.invocations, isEmpty);

      final job = (await outbox.byId(jobId))!;
      expect(job.status, SyncStatus.dead);
      expect(job.lastError, contains('No registration'));

      expect(failedEvents, hasLength(1));
      expect(failedEvents.single.retryable, isFalse);
      expect(failedEvents.single.error, contains('No registration'));
    });
  });
}
