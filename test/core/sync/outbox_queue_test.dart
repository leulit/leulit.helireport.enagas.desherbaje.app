import 'package:flutter_test/flutter_test.dart';
import 'package:helireport_desherbaje/core/sync/sync.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late OutboxQueue queue;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, _) => OutboxSchema.ensure(d),
      ),
    );
    queue = OutboxQueue(db);
  });

  tearDown(() async {
    await queue.dispose();
    await db.close();
  });

  group('OutboxQueue.enqueue', () {
    test('inserts a pending job with auto id', () async {
      final id = await queue.enqueue(
        entityType: 'actividad',
        entityId: 'client-1',
        operation: SyncOperation.create,
        payload: '{"foo":"bar"}',
      );
      expect(id, greaterThan(0));

      final job = await queue.byId(id);
      expect(job, isNotNull);
      expect(job!.entityType, 'actividad');
      expect(job.entityId, 'client-1');
      expect(job.operation, SyncOperation.create);
      expect(job.status, SyncStatus.pending);
      expect(job.attempts, 0);
      expect(job.payload, '{"foo":"bar"}');
    });

    test('replaces prior job for same (type,id,operation) triple', () async {
      final first = await queue.enqueue(
        entityType: 'actividad',
        entityId: 'client-1',
        operation: SyncOperation.update,
        payload: 'v1',
      );
      await queue.markSyncing(first);

      final second = await queue.enqueue(
        entityType: 'actividad',
        entityId: 'client-1',
        operation: SyncOperation.update,
        payload: 'v2',
      );

      expect(await queue.countPending(), 1);
      expect(second, isNot(equals(first)));
      final latest = (await queue.nextPending()).single;
      expect(latest.payload, 'v2');
      expect(latest.status, SyncStatus.pending);
    });

    test('allows different operations on the same entity', () async {
      await queue.enqueue(
        entityType: 'actividad',
        entityId: 'client-1',
        operation: SyncOperation.create,
      );
      await queue.enqueue(
        entityType: 'actividad',
        entityId: 'client-1',
        operation: SyncOperation.update,
      );
      expect(await queue.countPending(), 2);
    });
  });

  group('OutboxQueue.nextPending', () {
    test('respects FIFO by created_at + id and limit', () async {
      final first = await queue.enqueue(
        entityType: 't',
        entityId: 'a',
        operation: SyncOperation.create,
      );
      final second = await queue.enqueue(
        entityType: 't',
        entityId: 'b',
        operation: SyncOperation.create,
      );
      final third = await queue.enqueue(
        entityType: 't',
        entityId: 'c',
        operation: SyncOperation.create,
      );

      final batch = await queue.nextPending(limit: 2);
      expect(batch.map((j) => j.id), [first, second]);
      expect(batch.every((j) => j.status == SyncStatus.pending), isTrue);
      expect(third, greaterThan(second));
    });

    test('excludes non-pending jobs', () async {
      final id = await queue.enqueue(
        entityType: 't',
        entityId: 'a',
        operation: SyncOperation.create,
      );
      await queue.markSyncing(id);
      expect(await queue.nextPending(), isEmpty);
    });
  });

  group('OutboxQueue state transitions', () {
    late int jobId;

    setUp(() async {
      jobId = await queue.enqueue(
        entityType: 't',
        entityId: 'a',
        operation: SyncOperation.create,
        payload: '{}',
      );
    });

    test('markSyncing flips status and increments attempts', () async {
      await queue.markSyncing(jobId);
      final job = (await queue.byId(jobId))!;
      expect(job.status, SyncStatus.syncing);
      expect(job.attempts, 1);

      await queue.markPending(jobId, error: 'retry');
      await queue.markSyncing(jobId);
      final retried = (await queue.byId(jobId))!;
      expect(retried.attempts, 2);
    });

    test('markSynced stores remoteId and clears last_error', () async {
      await queue.markSyncing(jobId);
      await queue.markPending(jobId, error: 'temporary');
      await queue.markSyncing(jobId);
      await queue.markSynced(jobId, remoteId: 'remote-42');

      final job = (await queue.byId(jobId))!;
      expect(job.status, SyncStatus.synced);
      expect(job.remoteId, 'remote-42');
      expect(job.syncedAt, isNotNull);
      expect(job.lastError, isNull);
    });

    test('markPending persists the error message', () async {
      await queue.markSyncing(jobId);
      await queue.markPending(jobId, error: '503 Service Unavailable');
      final job = (await queue.byId(jobId))!;
      expect(job.status, SyncStatus.pending);
      expect(job.lastError, '503 Service Unavailable');
    });

    test('markDead transitions to dead with reason', () async {
      await queue.markDead(jobId, reason: 'Schema mismatch');
      final job = (await queue.byId(jobId))!;
      expect(job.status, SyncStatus.dead);
      expect(job.lastError, 'Schema mismatch');
    });
  });

  group('OutboxQueue counting', () {
    test('countPending includes pending and syncing, not synced/dead',
        () async {
      final a = await queue.enqueue(
        entityType: 't',
        entityId: 'a',
        operation: SyncOperation.create,
      );
      final b = await queue.enqueue(
        entityType: 't',
        entityId: 'b',
        operation: SyncOperation.create,
      );
      final c = await queue.enqueue(
        entityType: 't',
        entityId: 'c',
        operation: SyncOperation.create,
      );
      final d = await queue.enqueue(
        entityType: 't',
        entityId: 'd',
        operation: SyncOperation.create,
      );

      await queue.markSyncing(b);
      await queue.markSynced(c);
      await queue.markDead(d, reason: 'bad');

      expect(await queue.countPending(), 2);
      expect(await queue.countByStatus(SyncStatus.synced), 1);
      expect(await queue.countByStatus(SyncStatus.dead), 1);
      expect(a, isNotNull);
    });
  });

  group('OutboxQueue removal', () {
    test('removeForEntity deletes every job for a given entity', () async {
      await queue.enqueue(
        entityType: 'actividad',
        entityId: 'a',
        operation: SyncOperation.create,
      );
      await queue.enqueue(
        entityType: 'actividad',
        entityId: 'a',
        operation: SyncOperation.update,
      );
      await queue.enqueue(
        entityType: 'actividad',
        entityId: 'b',
        operation: SyncOperation.create,
      );

      await queue.removeForEntity(entityType: 'actividad', entityId: 'a');
      final remaining = await queue.nextPending();
      expect(remaining, hasLength(1));
      expect(remaining.single.entityId, 'b');
    });

    test('purgeSynced only deletes old synced rows', () async {
      final recent = await queue.enqueue(
        entityType: 't',
        entityId: 'recent',
        operation: SyncOperation.create,
      );
      await queue.markSynced(recent, remoteId: 'r1');

      final oldId = await queue.enqueue(
        entityType: 't',
        entityId: 'old',
        operation: SyncOperation.create,
      );
      await db.update(
        OutboxSchema.tableName,
        {
          'status': SyncStatus.synced.wireName,
          'synced_at': DateTime.now()
              .subtract(const Duration(days: 10))
              .millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [oldId],
      );

      final deleted = await queue.purgeSynced();
      expect(deleted, 1);
      expect(await queue.byId(recent), isNotNull);
      expect(await queue.byId(oldId), isNull);
    });
  });

  group('OutboxQueue.changes stream', () {
    test('emits after enqueue and state transitions', () async {
      final emitted = <void>[];
      final sub = queue.changes.listen(emitted.add);

      await queue.enqueue(
        entityType: 't',
        entityId: 'a',
        operation: SyncOperation.create,
      );
      await queue.markSyncing(1);
      await queue.markSynced(1);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();
      expect(emitted.length, greaterThanOrEqualTo(3));
    });
  });
}
