import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/core/sync/contracts/sync_job.dart';
import 'package:helireport_desherbaje/core/sync/outbox/outbox_queue.dart';

// Recreates only the sync_queue table — no plugin, no OfflineDatabase overhead.
Future<Database> _openInMemoryDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final db = await openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE sync_queue (
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
    },
  );
  return db;
}

void main() {
  late Database db;
  late OutboxQueue queue;

  setUp(() async {
    db = await _openInMemoryDb();
    queue = OutboxQueue(db);
  });

  tearDown(() async => db.close());

  // ─── enqueue ───────────────────────────────────────────────────────────────

  group('enqueue', () {
    test('stores a job with status=pending and attempts=0', () async {
      final id = await queue.enqueue(
        entityType: 'segmento',
        clientId: 'uuid-1',
        operation: SyncOperation.create,
      );

      final job = await queue.byId(id);
      expect(job, isNotNull);
      expect(job!.entityType, equals('segmento'));
      expect(job.clientId, equals('uuid-1'));
      expect(job.operation, equals(SyncOperation.create));
      expect(job.status, equals(SyncStatus.pending));
      expect(job.attempts, equals(0));
      expect(job.lastError, isNull);
    });

    test('is idempotent: re-enqueue resets attempts and status', () async {
      final id1 = await queue.enqueue(
        entityType: 'segmento',
        clientId: 'uuid-1',
        operation: SyncOperation.update,
      );

      // Simulate it was being synced
      await queue.markSyncing(id1);
      final syncing = await queue.byId(id1);
      expect(syncing!.status, equals(SyncStatus.syncing));
      expect(syncing.attempts, equals(1));

      // Re-enqueue same (entity_type, client_id, operation) triple
      await queue.enqueue(
        entityType: 'segmento',
        clientId: 'uuid-1',
        operation: SyncOperation.update,
      );

      // Old row is replaced: attempts reset to 0, status back to pending
      final reset = await queue.byId(id1);
      expect(reset?.status ?? SyncStatus.pending, equals(SyncStatus.pending));
      expect(reset?.attempts ?? 0, equals(0));
    });

    test('different operations for same entity coexist', () async {
      await queue.enqueue(
        entityType: 'imagen',
        clientId: 'uuid-2',
        operation: SyncOperation.create,
      );
      await queue.enqueue(
        entityType: 'imagen',
        clientId: 'uuid-2',
        operation: SyncOperation.update,
      );

      final pending = await queue.pendingJobs();
      expect(pending, hasLength(2));
    });
  });

  // ─── nextPending ───────────────────────────────────────────────────────────

  group('nextPending', () {
    test('returns pending jobs in FIFO order', () async {
      await queue.enqueue(
          entityType: 'seg', clientId: 'a', operation: SyncOperation.create);
      await queue.enqueue(
          entityType: 'seg', clientId: 'b', operation: SyncOperation.create);
      await queue.enqueue(
          entityType: 'seg', clientId: 'c', operation: SyncOperation.create);

      final jobs = await queue.nextPending();
      expect(jobs.map((j) => j.clientId).toList(), equals(['a', 'b', 'c']));
    });

    test('respects limit', () async {
      for (var i = 0; i < 5; i++) {
        await queue.enqueue(
          entityType: 'seg',
          clientId: 'id-$i',
          operation: SyncOperation.create,
        );
      }
      final jobs = await queue.nextPending(limit: 3);
      expect(jobs, hasLength(3));
    });

    test('filters by entityType', () async {
      await queue.enqueue(
          entityType: 'segmento', clientId: 'a', operation: SyncOperation.create);
      await queue.enqueue(
          entityType: 'imagen', clientId: 'b', operation: SyncOperation.create);

      final segs = await queue.nextPending(entityType: 'segmento');
      expect(segs, hasLength(1));
      expect(segs.first.entityType, equals('segmento'));
    });

    test('excludes syncing and synced jobs', () async {
      final id = await queue.enqueue(
          entityType: 'seg', clientId: 'a', operation: SyncOperation.create);
      await queue.markSyncing(id);

      final pending = await queue.nextPending();
      expect(pending, isEmpty);
    });
  });

  // ─── countPending ──────────────────────────────────────────────────────────

  group('countPending', () {
    test('returns 0 for empty queue', () async {
      expect(await queue.countPending(), equals(0));
    });

    test('counts only pending jobs', () async {
      final id1 = await queue.enqueue(
          entityType: 'seg', clientId: 'a', operation: SyncOperation.create);
      await queue.enqueue(
          entityType: 'seg', clientId: 'b', operation: SyncOperation.create);
      await queue.markSyncing(id1);

      expect(await queue.countPending(), equals(1));
    });

    test('filtered count by entityType', () async {
      await queue.enqueue(
          entityType: 'segmento', clientId: 'a', operation: SyncOperation.create);
      await queue.enqueue(
          entityType: 'imagen', clientId: 'b', operation: SyncOperation.create);

      expect(await queue.countPending(entityType: 'segmento'), equals(1));
      expect(await queue.countPending(entityType: 'imagen'), equals(1));
      expect(await queue.countPending(entityType: 'mensaje'), equals(0));
    });
  });

  // ─── status transitions ────────────────────────────────────────────────────

  group('markSyncing', () {
    test('increments attempts and sets status to syncing', () async {
      final id = await queue.enqueue(
          entityType: 'seg', clientId: 'x', operation: SyncOperation.update);

      await queue.markSyncing(id);
      final job = await queue.byId(id);

      expect(job!.status, equals(SyncStatus.syncing));
      expect(job.attempts, equals(1));
    });

    test('accumulates attempts on repeated calls', () async {
      final id = await queue.enqueue(
          entityType: 'seg', clientId: 'x', operation: SyncOperation.update);

      await queue.markSyncing(id);
      await queue.markPendingAgain(id, error: 'timeout');
      await queue.markSyncing(id);

      final job = await queue.byId(id);
      expect(job!.attempts, equals(2));
    });
  });

  group('markSynced', () {
    test('sets status to synced and stores remoteId', () async {
      final id = await queue.enqueue(
          entityType: 'seg', clientId: 'x', operation: SyncOperation.create);
      await queue.markSyncing(id);
      await queue.markSynced(id, remoteId: 'server-42');

      final job = await queue.byId(id);
      expect(job!.status, equals(SyncStatus.synced));
      expect(job.remoteId, equals('server-42'));
      expect(job.syncedAt, isNotNull);
      expect(job.lastError, isNull);
    });
  });

  group('markPendingAgain', () {
    test('resets status to pending with error message', () async {
      final id = await queue.enqueue(
          entityType: 'seg', clientId: 'x', operation: SyncOperation.update);
      await queue.markSyncing(id);
      await queue.markPendingAgain(id, error: 'Network timeout', statusCode: 408);

      final job = await queue.byId(id);
      expect(job!.status, equals(SyncStatus.pending));
      expect(job.lastError, equals('Network timeout'));
      expect(job.statusCode, equals(408));
    });
  });

  group('markRejected', () {
    test('sets status to rejected', () async {
      final id = await queue.enqueue(
          entityType: 'seg', clientId: 'x', operation: SyncOperation.create);
      await queue.markSyncing(id);
      await queue.markRejected(id, error: 'Validation failed', statusCode: 422);

      final job = await queue.byId(id);
      expect(job!.status, equals(SyncStatus.rejected));
      expect(job.lastError, equals('Validation failed'));
      expect(job.statusCode, equals(422));
    });
  });

  group('retryRejected', () {
    test('promotes rejected job back to pending and clears error', () async {
      final id = await queue.enqueue(
          entityType: 'seg', clientId: 'x', operation: SyncOperation.create);
      await queue.markSyncing(id);
      await queue.markRejected(id, error: 'Bad request', statusCode: 400);
      await queue.retryRejected(id);

      final job = await queue.byId(id);
      expect(job!.status, equals(SyncStatus.pending));
      expect(job.lastError, isNull);
      expect(job.statusCode, isNull);
    });

    test('does NOT change a pending job (guard on status=rejected)', () async {
      final id = await queue.enqueue(
          entityType: 'seg', clientId: 'x', operation: SyncOperation.create);
      // job is pending, not rejected
      await queue.retryRejected(id);

      final job = await queue.byId(id);
      expect(job!.status, equals(SyncStatus.pending)); // unchanged, but it was already pending
    });
  });

  // ─── removal ───────────────────────────────────────────────────────────────

  group('discardJob', () {
    test('removes the job from queue', () async {
      final id = await queue.enqueue(
          entityType: 'seg', clientId: 'x', operation: SyncOperation.create);
      await queue.discardJob(id);

      expect(await queue.byId(id), isNull);
      expect(await queue.countPending(), equals(0));
    });
  });

  group('removeForEntity', () {
    test('deletes all jobs for the given entity', () async {
      await queue.enqueue(
          entityType: 'imagen', clientId: 'img-1', operation: SyncOperation.create);
      await queue.enqueue(
          entityType: 'imagen', clientId: 'img-1', operation: SyncOperation.update);
      await queue.enqueue(
          entityType: 'segmento', clientId: 'seg-1', operation: SyncOperation.update);

      await queue.removeForEntity(entityType: 'imagen', clientId: 'img-1');

      expect(await queue.countPending(entityType: 'imagen'), equals(0));
      expect(await queue.countPending(entityType: 'segmento'), equals(1));
    });
  });

  group('purgeSynced', () {
    test('deletes synced rows older than threshold', () async {
      final id = await queue.enqueue(
          entityType: 'seg', clientId: 'x', operation: SyncOperation.create);
      await queue.markSyncing(id);
      await queue.markSynced(id, remoteId: '1');

      // Synced row exists
      expect(await queue.countPending(), equals(0));

      // Advance 1ms so synced_at < threshold (strict less-than in SQL)
      await Future.delayed(const Duration(milliseconds: 1));
      final deleted = await queue.purgeSynced(olderThan: Duration.zero);
      expect(deleted, equals(1));
    });

    test('does not delete recently synced rows', () async {
      final id = await queue.enqueue(
          entityType: 'seg', clientId: 'x', operation: SyncOperation.create);
      await queue.markSyncing(id);
      await queue.markSynced(id, remoteId: '1');

      // Purge with 7 days — the row was just synced, should survive
      final deleted = await queue.purgeSynced(olderThan: const Duration(days: 7));
      expect(deleted, equals(0));
    });

    test('does not delete pending rows', () async {
      await queue.enqueue(
          entityType: 'seg', clientId: 'y', operation: SyncOperation.update);

      final deleted = await queue.purgeSynced(olderThan: Duration.zero);
      expect(deleted, equals(0));
      expect(await queue.countPending(), equals(1));
    });
  });

  // ─── syncingJobs (NF-4) ────────────────────────────────────────────────────

  group('syncingJobs', () {
    test('returns only jobs with status=syncing', () async {
      final id1 = await queue.enqueue(
          entityType: 'segmento', clientId: 'cid-1', operation: SyncOperation.update);
      final id2 = await queue.enqueue(
          entityType: 'segmento', clientId: 'cid-2', operation: SyncOperation.update);
      await queue.enqueue(
          entityType: 'segmento', clientId: 'cid-3', operation: SyncOperation.update);

      await queue.markSyncing(id1);
      await queue.markSyncing(id2);
      // id3 stays pending

      final syncing = await queue.syncingJobs();
      expect(syncing, hasLength(2));
      final clientIds = syncing.map((j) => j.clientId).toSet();
      expect(clientIds, containsAll(['cid-1', 'cid-2']));
      expect(clientIds, isNot(contains('cid-3')));
    });

    test('filters by entityType when provided', () async {
      final id1 = await queue.enqueue(
          entityType: 'segmento', clientId: 'seg-1', operation: SyncOperation.update);
      final id2 = await queue.enqueue(
          entityType: 'imagen', clientId: 'img-1', operation: SyncOperation.create);
      await queue.markSyncing(id1);
      await queue.markSyncing(id2);

      final segSyncing = await queue.syncingJobs(entityType: 'segmento');
      expect(segSyncing, hasLength(1));
      expect(segSyncing.first.clientId, equals('seg-1'));

      final imgSyncing = await queue.syncingJobs(entityType: 'imagen');
      expect(imgSyncing, hasLength(1));
      expect(imgSyncing.first.clientId, equals('img-1'));
    });

    test('returns empty list when no jobs are syncing', () async {
      await queue.enqueue(
          entityType: 'segmento', clientId: 'cid-p', operation: SyncOperation.update);

      final syncing = await queue.syncingJobs(entityType: 'segmento');
      expect(syncing, isEmpty);
    });

    test('does not include pending or synced jobs', () async {
      final id = await queue.enqueue(
          entityType: 'segmento', clientId: 'cid-s', operation: SyncOperation.create);
      await queue.markSyncing(id);
      await queue.markSynced(id, remoteId: '1');

      await queue.enqueue(
          entityType: 'segmento', clientId: 'cid-p', operation: SyncOperation.update);

      final syncing = await queue.syncingJobs(entityType: 'segmento');
      expect(syncing, isEmpty,
          reason: 'synced and pending jobs must not appear in syncingJobs');
    });
  });
}
