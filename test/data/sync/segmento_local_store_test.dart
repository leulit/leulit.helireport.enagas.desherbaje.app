// Tests for SegmentoLocalStore — focus: upsert reconciliation, findByRemoteId,
// markSynced logging, and index-collision behaviour after dropping
// ConflictAlgorithm.replace.
//
// DB infra: sqflite_common_ffi in-memory, recreating the segmentos table and
// its unique partial index via store.migrate(db, 0, 1) — same pattern as
// outbox_queue_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/data/sync/segmento_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';

Future<Database> _openDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return openDatabase(inMemoryDatabasePath, version: 1);
}

/// Minimal segmento for tests. [id] == null means local-only.
SegmentoEntity _seg({
  required String clientId,
  int? id,
  EstadoActividad estado = EstadoActividad.propuesta,
  DateTime? updatedAt,
}) {
  final e = SegmentoEntity(id, 1, TipoInstalacion.lineal, [], clientId: clientId);
  e.descripcion = 'test';
  if (updatedAt != null) {
    // Force a specific updatedAt via fromJson round-trip.
    // We rebuild via the factory so _updatedAt is correctly set.
    return SegmentoEntity.fromJson({
      ...e.toJson(),
      'updated_at': updatedAt.toIso8601String(),
    });
  }
  return e;
}

void main() {
  late Database db;
  late SegmentoLocalStore store;

  setUp(() async {
    db = await _openDb();
    store = SegmentoLocalStore(db);
    await store.migrate(db, 0, 1);
  });

  tearDown(() async => db.close());

  // ─── upsert reconciliation ────────────────────────────────────────────────

  group('upsert', () {
    test(
      '(a) remote with different clientId but SAME id does NOT delete the local row',
      () async {
        // Arrange: local row with remoteId=42, clientId='local-cid'
        final local = _seg(clientId: 'local-cid', id: 42);
        await store.upsert(local);
        await store.markSynced(clientId: 'local-cid', remoteId: '42');

        // Act: attempt to upsert a remote entity with same id=42 but NEW clientId
        // (this simulates the bug: backend omits client_id → fromJson mints new UUID)
        final remote = _seg(clientId: 'brand-new-uuid', id: 42);

        // The ConflictAlgorithm.abort on the unique partial index means the insert
        // throws when there is already a row with id=42 and a different client_id.
        expect(
          () async => store.upsert(remote),
          throwsA(isA<DatabaseException>()),
        );

        // The original local row must still exist.
        final still = await store.findByClientId('local-cid');
        expect(still, isNotNull);
        expect(still!.id, equals(42));
      },
    );

    test(
      '(b) upsert with existing clientId updates in place (row count stays 1)',
      () async {
        final e = _seg(clientId: 'cid-1', id: 10);
        await store.upsert(e);

        // mutate and upsert again
        e.estado = EstadoActividad.ejecucion;
        await store.upsert(e);

        final all = await store.findAll();
        expect(all, hasLength(1));
        expect(all.first.estado, equals(EstadoActividad.ejecucion));
      },
    );

    test(
      '(c) new clientId + colliding id throws (surface instead of silent delete)',
      () async {
        await store.upsert(_seg(clientId: 'cid-a', id: 99));

        expect(
          () async => store.upsert(_seg(clientId: 'cid-b', id: 99)),
          throwsA(isA<DatabaseException>()),
        );
      },
    );

    test(
      '(d) upsert preserves synced_at after markSynced (update path)',
      () async {
        final e = _seg(clientId: 'cid-sync', id: 7);
        await store.upsert(e);
        await store.markSynced(clientId: 'cid-sync', remoteId: '7');

        // Verify synced_at is set
        final rows = await db.query('segmentos',
            where: 'client_id = ?', whereArgs: ['cid-sync']);
        expect(rows.first['synced_at'], isNotNull);

        // Second upsert (e.g. a pull update) — synced_at must survive
        e.descripcion = 'updated';
        await store.upsert(e);

        final rows2 = await db.query('segmentos',
            where: 'client_id = ?', whereArgs: ['cid-sync']);
        expect(rows2.first['synced_at'], isNotNull,
            reason: 'synced_at must be preserved after upsert update');
        expect(rows2.first['descripcion'], equals('updated'));
      },
    );
  });

  // ─── findByRemoteId ────────────────────────────────────────────────────────

  group('findByRemoteId', () {
    test('(d) numeric string finds the row', () async {
      await store.upsert(_seg(clientId: 'cid-r', id: 42));
      await store.markSynced(clientId: 'cid-r', remoteId: '42');

      final found = await store.findByRemoteId('42');
      expect(found, isNotNull);
      expect(found!.clientId, equals('cid-r'));
    });

    test('returns null when id does not match any row', () async {
      final found = await store.findByRemoteId('999');
      expect(found, isNull);
    });

    test('(e) non-numeric string returns null (A5 — no crash)', () async {
      // Should return null without throwing; the warning is logged internally.
      final found = await store.findByRemoteId('not-a-number');
      expect(found, isNull);
    });
  });

  // ─── markSynced ───────────────────────────────────────────────────────────

  group('markSynced', () {
    test('numeric remoteId sets id column', () async {
      await store.upsert(_seg(clientId: 'cid-ms', id: null));
      await store.markSynced(clientId: 'cid-ms', remoteId: '55');

      final rows = await db.query('segmentos',
          where: 'client_id = ?', whereArgs: ['cid-ms']);
      expect(rows.first['id'], equals(55));
      expect(rows.first['synced_at'], isNotNull);
    });

    test(
      '(f) non-numeric remoteId leaves id null and does not throw (A5)',
      () async {
        await store.upsert(_seg(clientId: 'cid-nan', id: null));
        // Should not throw; just logs a warning.
        await expectLater(
          store.markSynced(clientId: 'cid-nan', remoteId: 'server-uuid'),
          completes,
        );

        final rows = await db.query('segmentos',
            where: 'client_id = ?', whereArgs: ['cid-nan']);
        expect(rows.first['id'], isNull,
            reason: 'id must remain null when remoteId is non-numeric');
      },
    );
  });
}
