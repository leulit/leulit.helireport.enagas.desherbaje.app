// Tests for ImagenLocalStore — focus: findWhere by segmento_id, order, and
// empty-result path.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/data/sync/imagen_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/imagen_segmento_entity.dart';

Future<Database> _openDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return openDatabase(inMemoryDatabasePath, version: 1);
}

ImagenSegmentoEntity _img({
  required String clientId,
  required int segmentoId,
  DateTime? capturadaAt,
}) {
  final ts = capturadaAt ?? DateTime.utc(2025, 1, 1);
  return ImagenSegmentoEntity(
    clientId: clientId,
    actividadId: 0,
    segmentoId: segmentoId,
    tipoFoto: TipoFoto.antes,
    filename: '$clientId.jpg',
    ruta: '/tmp/$clientId.jpg',
    capturadaAt: ts,
  );
}

void main() {
  late Database db;
  late ImagenLocalStore store;

  setUp(() async {
    db = await _openDb();
    store = ImagenLocalStore(db);
    await store.migrate(db, 0, 1);
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
  });
}
