import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:helireport_desherbaje/core/sync/sync.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeSyncable implements Syncable {
  @override
  final String clientId;
  @override
  final String? remoteId;
  @override
  final DateTime updatedAt;
  final String name;

  const FakeSyncable({
    required this.clientId,
    required this.name,
    required this.updatedAt,
    this.remoteId,
  });

  @override
  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'remoteId': remoteId,
        'updatedAt': updatedAt.toIso8601String(),
        'name': name,
      };

  static FakeSyncable fromJson(Map<String, dynamic> json) => FakeSyncable(
        clientId: json['clientId'] as String,
        name: json['name'] as String,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        remoteId: json['remoteId'] as String?,
      );
}

class FakeLocalStore implements LocalStore<FakeSyncable> {
  final Database _db;
  final Set<String> failOnUpsertForClientId = <String>{};
  final Set<String> failOnDeleteForClientId = <String>{};

  FakeLocalStore(this._db);

  static const tableName = 'fake_entities';

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $tableName ('
      'client_id TEXT PRIMARY KEY, '
      'payload TEXT NOT NULL'
      ')',
    );
  }

  @override
  Future<void> upsert(FakeSyncable entity, {DatabaseExecutor? txn}) async {
    if (failOnUpsertForClientId.contains(entity.clientId)) {
      throw StateError('Injected upsert failure for ${entity.clientId}');
    }
    final executor = txn ?? _db;
    await executor.insert(
      tableName,
      {
        'client_id': entity.clientId,
        'payload': jsonEncode(entity.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String clientId, {DatabaseExecutor? txn}) async {
    if (failOnDeleteForClientId.contains(clientId)) {
      throw StateError('Injected delete failure for $clientId');
    }
    final executor = txn ?? _db;
    await executor.delete(
      tableName,
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  @override
  Future<FakeSyncable?> findByClientId(String clientId) async {
    final rows = await _db.query(
      tableName,
      where: 'client_id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FakeSyncable.fromJson(
      jsonDecode(rows.first['payload']! as String) as Map<String, dynamic>,
    );
  }

  @override
  Future<List<FakeSyncable>> findAll() async {
    final rows = await _db.query(tableName);
    return rows
        .map((r) => FakeSyncable.fromJson(
              jsonDecode(r['payload']! as String) as Map<String, dynamic>,
            ))
        .toList(growable: false);
  }

  @override
  Future<void> markSynced({
    required String clientId,
    String? remoteId,
    DatabaseExecutor? txn,
  }) async {
    // No-op for the fake: row shape doesn't track sync metadata.
  }

  Future<int> countRows() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM $tableName');
    return (rows.first['c'] as int?) ?? 0;
  }
}

class ThrowingRemoteAdapter implements RemoteAdapter<FakeSyncable> {
  @override
  Future<SyncOutcome<FakeSyncable>> push({
    required FakeSyncable entity,
    required SyncOperation operation,
  }) async {
    throw StateError('Remote push must not be invoked in these tests');
  }
}

/// Wrapper that can force `enqueue` to throw so we can exercise the rollback
/// path from the outbox side.
class FailingOutboxQueue extends OutboxQueue {
  bool throwOnEnqueue = false;

  FailingOutboxQueue(super.db);

  @override
  Future<int> enqueue({
    required String entityType,
    required String entityId,
    required SyncOperation operation,
    String? payload,
    DatabaseExecutor? txn,
  }) {
    if (throwOnEnqueue) {
      throw StateError('Injected enqueue failure');
    }
    return super.enqueue(
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: payload,
      txn: txn,
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late FailingOutboxQueue outbox;
  late FakeLocalStore store;
  late TypeRegistry registry;
  late SyncEngine engine;
  late OfflineRepository<FakeSyncable> repo;

  const entityType = 'fake';

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, _) async {
          await OutboxSchema.ensure(d);
          await FakeLocalStore.ensureSchema(d);
        },
      ),
    );
    outbox = FailingOutboxQueue(db);
    store = FakeLocalStore(db);
    registry = TypeRegistry();
    registry.register<FakeSyncable>(
      TypeRegistration<FakeSyncable>(
        entityType: entityType,
        adapter: ThrowingRemoteAdapter(),
        conflictResolver: const LastWriteWinsResolver<FakeSyncable>(),
        fromJson: FakeSyncable.fromJson,
        localStore: store,
      ),
    );
    engine = SyncEngine(
      outbox: outbox,
      registry: registry,
      isOnline: () => false, // keep drain idle during tests
    );
    repo = OfflineRepository<FakeSyncable>(
      entityType: entityType,
      db: db,
      store: store,
      outbox: outbox,
      engine: engine,
      isOnline: () => false, // prevents auto-drain
    );
  });

  tearDown(() async {
    await outbox.dispose();
    await db.close();
  });

  FakeSyncable makeEntity(String id, {String name = 'alpha'}) => FakeSyncable(
        clientId: id,
        name: name,
        updatedAt: DateTime(2026, 4, 19, 12, 0, 0),
      );

  group('OfflineRepository.create atomicity', () {
    test('commits both entity row and outbox row on success', () async {
      final entity = makeEntity('client-1');

      await repo.create(entity);

      expect(await store.countRows(), 1);
      expect(await store.findByClientId('client-1'), isNotNull);
      expect(await outbox.countPending(), 1);

      final jobs = await outbox.nextPending();
      expect(jobs, hasLength(1));
      expect(jobs.single.entityType, entityType);
      expect(jobs.single.entityId, 'client-1');
      expect(jobs.single.operation, SyncOperation.create);
    });

    test('rolls back both writes when LocalStore.upsert throws', () async {
      final entity = makeEntity('client-boom');
      store.failOnUpsertForClientId.add('client-boom');

      await expectLater(
        repo.create(entity),
        throwsA(isA<StateError>()),
      );

      expect(await store.countRows(), 0);
      expect(await store.findByClientId('client-boom'), isNull);
      expect(await outbox.countPending(), 0);
    });

    test('rolls back both writes when OutboxQueue.enqueue throws', () async {
      final entity = makeEntity('client-2');
      outbox.throwOnEnqueue = true;

      await expectLater(
        repo.create(entity),
        throwsA(isA<StateError>()),
      );

      expect(await store.countRows(), 0);
      expect(await store.findByClientId('client-2'), isNull);
      expect(await outbox.countPending(), 0);
    });
  });

  group('OfflineRepository.update atomicity', () {
    test('commits entity update and enqueues update job', () async {
      await repo.create(makeEntity('client-3', name: 'v1'));
      expect(await outbox.countPending(), 1);

      await repo.update(makeEntity('client-3', name: 'v2'));

      final stored = await store.findByClientId('client-3');
      expect(stored, isNotNull);
      expect(stored!.name, 'v2');

      // Same (type,id,create) was replaced by update triple; pending count
      // should include the create + the update rows (different operations).
      final pending = await outbox.nextPending();
      final ops = pending.map((j) => j.operation).toSet();
      expect(ops.contains(SyncOperation.update), isTrue);
    });

    test('rolls back update when enqueue throws', () async {
      await repo.create(makeEntity('client-4', name: 'v1'));
      final before = await outbox.countPending();

      outbox.throwOnEnqueue = true;
      await expectLater(
        repo.update(makeEntity('client-4', name: 'v2')),
        throwsA(isA<StateError>()),
      );

      // Local row must still reflect v1, and no extra outbox row added.
      final stored = await store.findByClientId('client-4');
      expect(stored!.name, 'v1');
      expect(await outbox.countPending(), before);
    });
  });

  group('OfflineRepository.delete atomicity', () {
    test('removes local row and enqueues delete job', () async {
      await repo.create(makeEntity('client-5'));
      expect(await store.findByClientId('client-5'), isNotNull);

      await repo.delete(makeEntity('client-5'));

      expect(await store.findByClientId('client-5'), isNull);
      final pending = await outbox.nextPending(limit: 50);
      expect(
        pending.any((j) =>
            j.entityId == 'client-5' && j.operation == SyncOperation.delete),
        isTrue,
      );
    });

    test('rolls back delete when enqueue throws', () async {
      await repo.create(makeEntity('client-6'));
      outbox.throwOnEnqueue = true;

      await expectLater(
        repo.delete(makeEntity('client-6')),
        throwsA(isA<StateError>()),
      );

      // Entity must still be present because the transaction rolled back.
      expect(await store.findByClientId('client-6'), isNotNull);
    });

    test('rolls back delete when LocalStore.delete throws', () async {
      await repo.create(makeEntity('client-7'));
      store.failOnDeleteForClientId.add('client-7');

      await expectLater(
        repo.delete(makeEntity('client-7')),
        throwsA(isA<StateError>()),
      );

      expect(await store.findByClientId('client-7'), isNotNull);
      // Create job still present; no delete job inserted.
      final pending = await outbox.nextPending(limit: 50);
      expect(
        pending.any((j) =>
            j.entityId == 'client-7' && j.operation == SyncOperation.delete),
        isFalse,
      );
    });
  });
}
