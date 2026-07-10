// Tests for ImagenLocalStore — focus: findWhere by segmento_id, order, and
// empty-result path.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/data/sync/imagen_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/imagen_segmento_entity.dart';

Future<Database> _openDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  // singleInstance: false — otherwise sqflite_ffi caches connections by path
  // and reopening `inMemoryDatabasePath` within the same test run returns the
  // SAME underlying database, leaking schema state between tests.
  return openDatabase(inMemoryDatabasePath, version: 1, singleInstance: false);
}

ImagenSegmentoEntity _img({
  required String clientId,
  required int segmentoId,
  DateTime? capturadaAt,
  String? segmentoClientId,
  String? gisJson,
}) {
  final ts = capturadaAt ?? DateTime.utc(2025, 1, 1);
  return ImagenSegmentoEntity(
    clientId: clientId,
    actividadId: 0,
    segmentoId: segmentoId,
    segmentoClientId: segmentoClientId,
    tipoFoto: TipoFoto.antes,
    filename: '$clientId.jpg',
    ruta: '/tmp/$clientId.jpg',
    capturadaAt: ts,
  )..gisJson = gisJson;
}

void main() {
  late Database db;
  late ImagenLocalStore store;

  setUp(() async {
    db = await _openDb();
    store = ImagenLocalStore(db);
    await store.migrate(db, 0, 3);
  });

  tearDown(() async => db.close());

  group('findWhere', () {
    test('returns imagenes for matching segmento_id', () async {
      await store.upsert(_img(clientId: 'img-a', segmentoId: 10));
      await store.upsert(_img(clientId: 'img-b', segmentoId: 10));
      await store.upsert(_img(clientId: 'img-c', segmentoId: 20));

      final result = await store.findWhere('segmento_id', 10);
      expect(result.length, equals(2));
      final ids = result.map((i) => i.clientId).toSet();
      expect(ids, containsAll(['img-a', 'img-b']));
    });

    test('returns empty list when no row matches', () async {
      await store.upsert(_img(clientId: 'img-x', segmentoId: 1));
      final result = await store.findWhere('segmento_id', 999);
      expect(result, isEmpty);
    });

    test('order is capturada_at DESC', () async {
      final earlier = DateTime.utc(2025, 1, 1);
      final later = DateTime.utc(2025, 6, 1);

      await store.upsert(_img(clientId: 'old', segmentoId: 5, capturadaAt: earlier));
      await store.upsert(_img(clientId: 'new', segmentoId: 5, capturadaAt: later));

      final result = await store.findWhere('segmento_id', 5);
      expect(result.first.clientId, equals('new'));
      expect(result.last.clientId, equals('old'));
    });

    test('gis_json round-trips through the store', () async {
      await store.upsert(_img(
        clientId: 'img-gis',
        segmentoId: 10,
        gisJson: '{"type":"FeatureCollection","features":[]}',
      ));

      final result = await store.findWhere('segmento_id', 10);
      expect(result.length, equals(1));
      expect(
        result.first.gisJson,
        equals('{"type":"FeatureCollection","features":[]}'),
      );
    });
  });

  group('findWhere by segmento_client_id', () {
    test('returns imagenes for matching segmento_client_id', () async {
      await store.upsert(_img(
          clientId: 'img-a', segmentoId: 0, segmentoClientId: 'seg-A'));
      await store.upsert(_img(
          clientId: 'img-b', segmentoId: 0, segmentoClientId: 'seg-A'));
      await store.upsert(_img(
          clientId: 'img-c', segmentoId: 0, segmentoClientId: 'seg-B'));

      final result = await store.findWhere('segmento_client_id', 'seg-A');
      expect(result.length, equals(2));
      final ids = result.map((i) => i.clientId).toSet();
      expect(ids, containsAll(['img-a', 'img-b']));
    });

    test('returns empty list when no row matches', () async {
      await store.upsert(_img(
          clientId: 'img-x', segmentoId: 0, segmentoClientId: 'seg-known'));
      final result =
          await store.findWhere('segmento_client_id', 'seg-unknown');
      expect(result, isEmpty);
    });
  });

  group('stepwise migration 0→1→2→3', () {
    test('column is usable after migrating step by step', () async {
      final freshDb = await _openDb();
      final freshStore = ImagenLocalStore(freshDb);
      await freshStore.migrate(freshDb, 0, 1);
      await freshStore.migrate(freshDb, 1, 2);
      await freshStore.migrate(freshDb, 2, 3);

      await freshStore.upsert(_img(
        clientId: 'step-a',
        segmentoId: 0,
        segmentoClientId: 'seg-step',
        gisJson: '{"type":"FeatureCollection","features":[]}',
      ));
      final result =
          await freshStore.findWhere('segmento_client_id', 'seg-step');
      expect(result.length, equals(1));
      expect(result.first.clientId, equals('step-a'));
      expect(
        result.first.gisJson,
        equals('{"type":"FeatureCollection","features":[]}'),
      );

      await freshDb.close();
    });
  });
}
