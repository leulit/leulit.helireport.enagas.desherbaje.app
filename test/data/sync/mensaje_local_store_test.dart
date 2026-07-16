// Tests for MensajeLocalStore — focus: findWhere, findBySegmento equivalence,
// order, and empty-result path.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/data/sync/mensaje_local_store.dart';
import 'package:helireport_desherbaje/data/model/mensaje_entity.dart';

Future<Database> _openDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return openDatabase(inMemoryDatabasePath, version: 1);
}

MensajeSegmentoEntity _msg({
  required String clientId,
  required int segmentoId,
  String? segmentoClientId,
  DateTime? createdAt,
}) {
  final ts = createdAt ?? DateTime.utc(2025, 1, 1);
  return MensajeSegmentoEntity(
    clientId: clientId,
    segmentoId: segmentoId,
    segmentoClientId: segmentoClientId,
    mensaje: 'test message',
    createdAt: ts,
    updatedAt: ts,
  );
}

void main() {
  late Database db;
  late MensajeLocalStore store;

  setUp(() async {
    db = await _openDb();
    store = MensajeLocalStore(db);
    await store.migrate(db, 0, store.schemaVersion);
  });

  tearDown(() async => db.close());

  group('findWhere', () {
    test('returns mensajes for matching segmento_id', () async {
      await store.upsert(_msg(clientId: 'msg-a', segmentoId: 10));
      await store.upsert(_msg(clientId: 'msg-b', segmentoId: 10));
      await store.upsert(_msg(clientId: 'msg-c', segmentoId: 20));

      final result = await store.findWhere('segmento_id', 10);
      expect(result.length, equals(2));
      final ids = result.map((m) => m.clientId).toSet();
      expect(ids, containsAll(['msg-a', 'msg-b']));
    });

    test('returns empty list when no row matches', () async {
      await store.upsert(_msg(clientId: 'msg-x', segmentoId: 1));
      final result = await store.findWhere('segmento_id', 999);
      expect(result, isEmpty);
    });

    test('order is created_at DESC', () async {
      final earlier = DateTime.utc(2025, 1, 1);
      final later = DateTime.utc(2025, 6, 1);

      await store.upsert(_msg(clientId: 'old', segmentoId: 5, createdAt: earlier));
      await store.upsert(_msg(clientId: 'new', segmentoId: 5, createdAt: later));

      final result = await store.findWhere('segmento_id', 5);
      expect(result.first.clientId, equals('new'));
      expect(result.last.clientId, equals('old'));
    });
  });

  group('findBySegmento is equivalent to findWhere', () {
    test('findWhere and findBySegmento return same results', () async {
      final ts1 = DateTime.utc(2025, 1, 1);
      final ts2 = DateTime.utc(2025, 3, 1);

      await store.upsert(_msg(clientId: 'm1', segmentoId: 42, createdAt: ts2));
      await store.upsert(_msg(clientId: 'm2', segmentoId: 42, createdAt: ts1));
      await store.upsert(_msg(clientId: 'm3', segmentoId: 99));

      final viaFindWhere = await store.findWhere('segmento_id', 42);
      final viaFindBySegmento = await store.findBySegmento(42);

      expect(viaFindWhere.length, equals(2));
      expect(viaFindBySegmento.length, equals(2));

      // Same order (created_at DESC)
      expect(
        viaFindWhere.map((m) => m.clientId).toList(),
        equals(viaFindBySegmento.map((m) => m.clientId).toList()),
      );
    });
  });

  group('segmento_client_id (v2)', () {
    test('round-trips the segmento_client_id column', () async {
      await store.upsert(_msg(
        clientId: 'm1',
        segmentoId: 0, // parent not synced yet
        segmentoClientId: 'seg-uuid-1',
      ));

      final row = await store.findByClientId('m1');
      expect(row, isNotNull);
      expect(row!.segmentoClientId, equals('seg-uuid-1'));
    });

    test('findBySegmentoClientId filters by the local parent id', () async {
      await store.upsert(
          _msg(clientId: 'a', segmentoId: 0, segmentoClientId: 'seg-1'));
      await store.upsert(
          _msg(clientId: 'b', segmentoId: 0, segmentoClientId: 'seg-1'));
      await store.upsert(
          _msg(clientId: 'c', segmentoId: 0, segmentoClientId: 'seg-2'));

      final result = await store.findBySegmentoClientId('seg-1');
      expect(result.map((m) => m.clientId).toSet(), {'a', 'b'});
    });
  });

  group('v1 → v2 migration', () {
    test('adds segmento_client_id and preserves existing rows', () async {
      // Isolated connection (singleInstance:false) so it does not share the
      // shared in-memory DB that setUp already migrated to v2.
      final db2 =
          await openDatabase(inMemoryDatabasePath, singleInstance: false);
      addTearDown(() async => db2.close());
      const table = 'mensajes_segmento';

      // Build the ORIGINAL v1 schema (no segmento_client_id) + one row.
      await db2.execute('''
        CREATE TABLE $table (
          client_id    TEXT PRIMARY KEY,
          id           INTEGER,
          segmento_id  INTEGER NOT NULL,
          mensaje      TEXT    NOT NULL,
          enviado_por  INTEGER,
          created_at   TEXT    NOT NULL,
          updated_at   TEXT    NOT NULL,
          synced_at    TEXT
        )
      ''');
      await db2.insert(table, {
        'client_id': 'legacy',
        'id': 7,
        'segmento_id': 3,
        'mensaje': 'antiguo',
        'created_at': '2025-01-01T00:00:00.000Z',
        'updated_at': '2025-01-01T00:00:00.000Z',
      });

      // Run the actual v1 → v2 migration.
      final store2 = MensajeLocalStore(db2);
      await store2.migrate(db2, 1, 2);

      // Existing row survives, new column present and null.
      final legacy = await store2.findByClientId('legacy');
      expect(legacy, isNotNull);
      expect(legacy!.mensaje, equals('antiguo'));
      expect(legacy.segmentoClientId, isNull);

      // The new column is writable/queryable.
      await store2.upsert(_msg(
        clientId: 'nuevo',
        segmentoId: 0,
        segmentoClientId: 'seg-x',
      ));
      final byParent = await store2.findBySegmentoClientId('seg-x');
      expect(byParent.map((m) => m.clientId), contains('nuevo'));
    });
  });
}
