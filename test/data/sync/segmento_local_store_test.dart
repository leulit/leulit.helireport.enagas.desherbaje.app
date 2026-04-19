import 'package:flutter_test/flutter_test.dart';
import 'package:helireport_desherbaje/data/sync/actividad_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/actividad_entity.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _createActividadesTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE actividades (
      id              INTEGER PRIMARY KEY,
      posicion_id     INTEGER NOT NULL DEFAULT 0,
      estado          TEXT NOT NULL DEFAULT 'Propuesta',
      descripcion     TEXT NOT NULL DEFAULT '',
      superficie_m2   REAL NOT NULL DEFAULT 0.0,
      coste_estimado  REAL NOT NULL DEFAULT 0.0,
      fecha_programada TEXT,
      fecha_inicio    TEXT,
      fecha_fin       TEXT,
      segmentos_json  TEXT,
      synced_at       TEXT,
      needs_sync      INTEGER NOT NULL DEFAULT 0
    )
  ''');
}

ActividadEntity _makeActividad({
  required int id,
  EstadoActividad estado = EstadoActividad.propuesta,
  String descripcion = 'test',
  DateTime? fechaProgramada,
  int segmentoCount = 1,
}) {
  final segmentos = List<SegmentoEntity>.generate(
    segmentoCount,
    (i) => SegmentoEntity(
      id: i,
      ctId: 1,
      actividadId: id,
      nombre: 'seg-$i',
      descripcion: null,
      traza: null,
      tipoInstalacion: TipoInstalacion.lineal,
      tipoActividad: TipoActividad.desherbajeSelectivo,
      estado: estado,
      pkInicio: null,
      pkFin: null,
      latInicio: null,
      lngInicio: null,
      latFin: null,
      lngFin: null,
      ubicacionGis: const <LatLng>[],
    ),
  );
  return ActividadEntity(
    id: id,
    posicionId: 10,
    estado: estado,
    descripcion: descripcion,
    superficieM2: 123.4,
    costeEstimado: 99.9,
    fechaProgramada: fechaProgramada ?? DateTime(2026, 4, 19, 8),
    fechaInicio: DateTime(2026, 4, 19, 9),
    fechaFin: DateTime(2026, 4, 19, 18),
    segmentos: segmentos,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late ActividadLocalStore store;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, _) async {
          await _createActividadesTable(d);
        },
      ),
    );
    store = ActividadLocalStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('ActividadLocalStore.upsert / findByClientId', () {
    test('roundtrips entity fields and segmentos', () async {
      final entity = _makeActividad(
        id: 42,
        estado: EstadoActividad.ejecucion,
        descripcion: 'unit test desc',
        segmentoCount: 3,
      );

      await store.upsert(entity);

      final loaded = await store.findByClientId('act-42');
      expect(loaded, isNotNull);
      expect(loaded!.id, 42);
      expect(loaded.estado, EstadoActividad.ejecucion);
      expect(loaded.descripcion, 'unit test desc');
      expect(loaded.segmentos, hasLength(3));
    });

    test('findByClientId returns null when no row', () async {
      expect(await store.findByClientId('act-999'), isNull);
    });

    test('invalid clientId shape throws ArgumentError', () async {
      expect(
        () => store.findByClientId('bad-7'),
        throwsArgumentError,
      );
      expect(
        () => store.findByClientId('act-notanint'),
        throwsArgumentError,
      );
    });
  });

  group('ActividadLocalStore.markSynced', () {
    test('upsert sets needs_sync = 1; markSynced flips to 0 and sets synced_at',
        () async {
      final entity = _makeActividad(id: 7);
      await store.upsert(entity);

      final afterUpsert = await db.query(
        'actividades',
        columns: ['needs_sync', 'synced_at'],
        where: 'id = ?',
        whereArgs: [7],
      );
      expect(afterUpsert.single['needs_sync'], 1);
      expect(afterUpsert.single['synced_at'], isNull);

      await store.markSynced(clientId: 'act-7', remoteId: '7');

      final afterSync = await db.query(
        'actividades',
        columns: ['needs_sync', 'synced_at'],
        where: 'id = ?',
        whereArgs: [7],
      );
      expect(afterSync.single['needs_sync'], 0);
      expect(afterSync.single['synced_at'], isA<String>());
      expect((afterSync.single['synced_at']! as String).isNotEmpty, isTrue);
    });
  });

  group('ActividadLocalStore.delete', () {
    test('delete by clientId removes the row', () async {
      await store.upsert(_makeActividad(id: 1));
      await store.upsert(_makeActividad(id: 2));

      await store.delete('act-1');

      expect(await store.findByClientId('act-1'), isNull);
      expect(await store.findByClientId('act-2'), isNotNull);
    });
  });

  group('ActividadLocalStore.findAll', () {
    test('orders by fecha_programada DESC', () async {
      await store.upsert(_makeActividad(
        id: 1,
        fechaProgramada: DateTime(2026, 1, 1),
      ));
      await store.upsert(_makeActividad(
        id: 2,
        fechaProgramada: DateTime(2026, 5, 1),
      ));
      await store.upsert(_makeActividad(
        id: 3,
        fechaProgramada: DateTime(2026, 3, 1),
      ));

      final all = await store.findAll();
      expect(all.map((a) => a.id).toList(), [2, 3, 1]);
    });
  });

  group('ActividadLocalStore txn discipline', () {
    test('upsert inside a throwing transaction is rolled back', () async {
      expect(
        () => db.transaction((txn) async {
          await store.upsert(_makeActividad(id: 100), txn: txn);
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );

      // Give the transaction a microtask to settle before assertion.
      await Future<void>.delayed(Duration.zero);
      expect(await store.findByClientId('act-100'), isNull);
    });

    test('delete inside a throwing transaction is rolled back', () async {
      await store.upsert(_makeActividad(id: 101));

      expect(
        () => db.transaction((txn) async {
          await store.delete('act-101', txn: txn);
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );

      await Future<void>.delayed(Duration.zero);
      expect(await store.findByClientId('act-101'), isNotNull);
    });

    test('markSynced inside a throwing transaction is rolled back', () async {
      await store.upsert(_makeActividad(id: 102));

      expect(
        () => db.transaction((txn) async {
          await store.markSynced(
            clientId: 'act-102',
            remoteId: '102',
            txn: txn,
          );
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );

      await Future<void>.delayed(Duration.zero);
      final row = await db.query(
        'actividades',
        columns: ['needs_sync', 'synced_at'],
        where: 'id = ?',
        whereArgs: [102],
      );
      expect(row.single['needs_sync'], 1);
      expect(row.single['synced_at'], isNull);
    });
  });
}
