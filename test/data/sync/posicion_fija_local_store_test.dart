// Tests for PosicionFijaLocalStore — focus: upsert reconciliation,
// findByRemoteId, markSynced logging, and index-collision behaviour. Clone
// of segmento_local_store_test.dart adapted to the pull-only entity.
//
// DB infra: sqflite_common_ffi in-memory, recreating the posiciones_fijas
// table and its unique partial index via store.migrate(db, 0, 1) — same
// pattern as segmento_local_store_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/data/sync/posicion_fija_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/posicion_fija_entity.dart';

Future<Database> _openDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return openDatabase(inMemoryDatabasePath, version: 1);
}

/// Minimal posición fija for tests. [id] == null means never synced.
PosicionFijaEntity _pos({
  required String clientId,
  int? id,
  String title = 'Posición test',
  String ctname = 'CT1',
}) {
  return PosicionFijaEntity(
    id: id,
    clientId: clientId,
    title: title,
    ctname: ctname,
  );
}

void main() {
  late Database db;
  late PosicionFijaLocalStore store;

  setUp(() async {
    db = await _openDb();
    store = PosicionFijaLocalStore(db);
    await store.migrate(db, 0, 1);
  });

  tearDown(() async => db.close());

  // ─── upsert reconciliation ────────────────────────────────────────────────

  group('upsert', () {
    test(
      '(a) remote with different clientId but SAME id does NOT delete the local row',
      () async {
        final local = _pos(clientId: 'local-cid', id: 42);
        await store.upsert(local);
        await store.markSynced(clientId: 'local-cid', remoteId: '42');

        final remote = _pos(clientId: 'brand-new-uuid', id: 42);

        expect(
          () async => store.upsert(remote),
          throwsA(isA<DatabaseException>()),
        );

        final still = await store.findByClientId('local-cid');
        expect(still, isNotNull);
        expect(still!.id, equals(42));
      },
    );

    test(
      '(b) upsert with existing clientId updates in place (row count stays 1)',
      () async {
        final e = _pos(clientId: 'cid-1', id: 10, title: 'Original');
        await store.upsert(e);

        final updated = e.copyWith(title: 'Modificado');
        await store.upsert(updated);

        final all = await store.findAll();
        expect(all, hasLength(1));
        expect(all.first.title, equals('Modificado'));
      },
    );

    test(
      '(c) new clientId + colliding id throws (surface instead of silent delete)',
      () async {
        await store.upsert(_pos(clientId: 'cid-a', id: 99));

        expect(
          () async => store.upsert(_pos(clientId: 'cid-b', id: 99)),
          throwsA(isA<DatabaseException>()),
        );
      },
    );

    test(
      '(d) upsert preserves synced_at after markSynced (update path)',
      () async {
        final e = _pos(clientId: 'cid-sync', id: 7);
        await store.upsert(e);
        await store.markSynced(clientId: 'cid-sync', remoteId: '7');

        final rows = await db.query('posiciones_fijas',
            where: 'client_id = ?', whereArgs: ['cid-sync']);
        expect(rows.first['synced_at'], isNotNull);

        final updated = e.copyWith(title: 'updated');
        await store.upsert(updated);

        final rows2 = await db.query('posiciones_fijas',
            where: 'client_id = ?', whereArgs: ['cid-sync']);
        expect(rows2.first['synced_at'], isNotNull,
            reason: 'synced_at must be preserved after upsert update');
        expect(rows2.first['title'], equals('updated'));
      },
    );
  });

  // ─── findByRemoteId ────────────────────────────────────────────────────────

  group('findByRemoteId', () {
    test('(d) numeric string finds the row', () async {
      await store.upsert(_pos(clientId: 'cid-r', id: 42));
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
      final found = await store.findByRemoteId('not-a-number');
      expect(found, isNull);
    });
  });

  // ─── findWhere ────────────────────────────────────────────────────────────

  group('findWhere', () {
    test('returns rows matching column value', () async {
      await store.upsert(_pos(clientId: 'ct1-a', ctname: 'CT1'));
      await store.upsert(_pos(clientId: 'ct1-b', ctname: 'CT1'));
      await store.upsert(_pos(clientId: 'ct2-a', ctname: 'CT2'));

      final result = await store.findWhere('ctname', 'CT1');
      expect(result.length, equals(2));
      final ids = result.map((s) => s.clientId).toSet();
      expect(ids, containsAll(['ct1-a', 'ct1-b']));
    });

    test('returns empty list when no rows match', () async {
      await store.upsert(_pos(clientId: 'some-pos'));
      final result = await store.findWhere('ctname', 'NOPE');
      expect(result, isEmpty);
    });
  });

  // ─── markSynced ───────────────────────────────────────────────────────────

  group('markSynced', () {
    test('numeric remoteId sets id column', () async {
      await store.upsert(_pos(clientId: 'cid-ms', id: null));
      await store.markSynced(clientId: 'cid-ms', remoteId: '55');

      final rows = await db.query('posiciones_fijas',
          where: 'client_id = ?', whereArgs: ['cid-ms']);
      expect(rows.first['id'], equals(55));
      expect(rows.first['synced_at'], isNotNull);
    });

    test(
      '(f) non-numeric remoteId leaves id null and does not throw (A5)',
      () async {
        await store.upsert(_pos(clientId: 'cid-nan', id: null));
        await expectLater(
          store.markSynced(clientId: 'cid-nan', remoteId: 'server-uuid'),
          completes,
        );

        final rows = await db.query('posiciones_fijas',
            where: 'client_id = ?', whereArgs: ['cid-nan']);
        expect(rows.first['id'], isNull,
            reason: 'id must remain null when remoteId is non-numeric');
      },
    );
  });
}
