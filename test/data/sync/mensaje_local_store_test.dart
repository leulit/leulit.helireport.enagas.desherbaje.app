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
  DateTime? createdAt,
}) {
  final ts = createdAt ?? DateTime.utc(2025, 1, 1);
  return MensajeSegmentoEntity(
    clientId: clientId,
    segmentoId: segmentoId,
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
    await store.migrate(db, 0, 1);
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
}
