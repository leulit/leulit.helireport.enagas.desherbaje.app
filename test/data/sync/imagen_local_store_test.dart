import 'package:flutter_test/flutter_test.dart';
import 'package:helireport_desherbaje/data/sync/imagen_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/imagen_segmento_entity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _createImagenesTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE imagenes_actividad (
      local_id        TEXT PRIMARY KEY,
      remote_id       INTEGER,
      actividad_id    INTEGER NOT NULL,
      segmento_id     INTEGER,
      local_path      TEXT NOT NULL,
      remote_url      TEXT,
      tipo_foto       TEXT NOT NULL,
      captured_at     TEXT NOT NULL,
      latitude        REAL,
      longitude       REAL,
      sync_status     TEXT NOT NULL DEFAULT 'pending',
      created_at      TEXT NOT NULL DEFAULT (datetime('now'))
    )
  ''');
}

ImagenSegmentoEntity _makeImagen({
  required String localId,
  int? remoteIntId,
  int actividadId = 100,
  int? segmentoId = 7,
  String localPath = '/tmp/img.jpg',
  String? remoteUrl,
  TipoFoto tipoFoto = TipoFoto.antes,
  DateTime? capturedAt,
  double? latitude = 40.4168,
  double? longitude = -3.7038,
  SyncStatus syncStatus = SyncStatus.pending,
}) {
  return ImagenSegmentoEntity(
    localId: localId,
    remoteIntId: remoteIntId,
    actividadId: actividadId,
    segmentoId: segmentoId,
    localPath: localPath,
    remoteUrl: remoteUrl,
    tipoFoto: tipoFoto,
    capturedAt: capturedAt ?? DateTime(2026, 4, 19, 12, 0, 0),
    latitude: latitude,
    longitude: longitude,
    syncStatus: syncStatus,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late ImagenLocalStore store;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, _) async {
          await _createImagenesTable(d);
        },
      ),
    );
    store = ImagenLocalStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('ImagenLocalStore.upsert / findByClientId', () {
    test('roundtrips every field of the entity', () async {
      final captured = DateTime(2026, 4, 19, 9, 30, 15);
      final entity = _makeImagen(
        localId: 'uuid-roundtrip',
        actividadId: 501,
        segmentoId: 77,
        localPath: '/storage/emulated/img-99.jpg',
        tipoFoto: TipoFoto.despues,
        capturedAt: captured,
        latitude: 41.1,
        longitude: -3.5,
        syncStatus: SyncStatus.pending,
      );

      await store.upsert(entity);

      final loaded = await store.findByClientId('uuid-roundtrip');
      expect(loaded, isNotNull);
      expect(loaded!.localId, 'uuid-roundtrip');
      expect(loaded.actividadId, 501);
      expect(loaded.segmentoId, 77);
      expect(loaded.localPath, '/storage/emulated/img-99.jpg');
      expect(loaded.tipoFoto, TipoFoto.despues);
      expect(loaded.capturedAt, captured);
      expect(loaded.latitude, 41.1);
      expect(loaded.longitude, -3.5);
      expect(loaded.syncStatus, SyncStatus.pending);
      expect(loaded.remoteIntId, isNull);
      expect(loaded.remoteUrl, isNull);
    });

    test('findByClientId returns null when row is absent', () async {
      expect(await store.findByClientId('does-not-exist'), isNull);
    });

    test('upsert replaces existing row with same local_id', () async {
      await store.upsert(_makeImagen(
        localId: 'repeat',
        tipoFoto: TipoFoto.antes,
      ));
      await store.upsert(_makeImagen(
        localId: 'repeat',
        tipoFoto: TipoFoto.despues,
        syncStatus: SyncStatus.uploading,
      ));

      final loaded = await store.findByClientId('repeat');
      expect(loaded, isNotNull);
      expect(loaded!.tipoFoto, TipoFoto.despues);
      expect(loaded.syncStatus, SyncStatus.uploading);

      final rows = await db.query('imagenes_actividad');
      expect(rows, hasLength(1));
    });
  });

  group('ImagenLocalStore.delete', () {
    test('removes the row by clientId', () async {
      await store.upsert(_makeImagen(localId: 'a'));
      await store.upsert(_makeImagen(localId: 'b'));

      await store.delete('a');

      expect(await store.findByClientId('a'), isNull);
      expect(await store.findByClientId('b'), isNotNull);
    });
  });

  group('ImagenLocalStore.findAll', () {
    test('orders by captured_at DESC', () async {
      await store.upsert(_makeImagen(
        localId: 'old',
        capturedAt: DateTime(2026, 1, 1, 8),
      ));
      await store.upsert(_makeImagen(
        localId: 'newest',
        capturedAt: DateTime(2026, 5, 1, 8),
      ));
      await store.upsert(_makeImagen(
        localId: 'middle',
        capturedAt: DateTime(2026, 3, 1, 8),
      ));

      final all = await store.findAll();
      expect(all.map((e) => e.localId).toList(), ['newest', 'middle', 'old']);
    });
  });

  group('ImagenLocalStore.markSynced', () {
    test('with numeric remoteId sets sync_status=uploaded and remote_id',
        () async {
      await store.upsert(_makeImagen(localId: 'to-mark'));

      await store.markSynced(clientId: 'to-mark', remoteId: '42');

      final row = (await db.query(
        'imagenes_actividad',
        where: 'local_id = ?',
        whereArgs: ['to-mark'],
      )).single;
      expect(row['sync_status'], SyncStatus.uploaded.name);
      expect(row['remote_id'], 42);
    });

    test('with null remoteId sets sync_status=uploaded without touching remote_id',
        () async {
      await store.upsert(_makeImagen(
        localId: 'to-mark-null',
        remoteIntId: 11,
      ));

      await store.markSynced(clientId: 'to-mark-null');

      final row = (await db.query(
        'imagenes_actividad',
        where: 'local_id = ?',
        whereArgs: ['to-mark-null'],
      )).single;
      expect(row['sync_status'], SyncStatus.uploaded.name);
      expect(row['remote_id'], 11);
    });

    test('with non-numeric remoteId leaves remote_id untouched but flips status',
        () async {
      await store.upsert(_makeImagen(
        localId: 'to-mark-bad',
        remoteIntId: 5,
      ));

      await store.markSynced(clientId: 'to-mark-bad', remoteId: 'abc');

      final row = (await db.query(
        'imagenes_actividad',
        where: 'local_id = ?',
        whereArgs: ['to-mark-bad'],
      )).single;
      expect(row['sync_status'], SyncStatus.uploaded.name);
      expect(row['remote_id'], 5);
    });
  });

  group('ImagenLocalStore txn discipline', () {
    test('upsert inside a throwing transaction is rolled back', () async {
      expect(
        () => db.transaction((txn) async {
          await store.upsert(_makeImagen(localId: 'txn-up'), txn: txn);
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );

      await Future<void>.delayed(Duration.zero);
      expect(await store.findByClientId('txn-up'), isNull);
    });

    test('delete inside a throwing transaction is rolled back', () async {
      await store.upsert(_makeImagen(localId: 'txn-del'));

      expect(
        () => db.transaction((txn) async {
          await store.delete('txn-del', txn: txn);
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );

      await Future<void>.delayed(Duration.zero);
      expect(await store.findByClientId('txn-del'), isNotNull);
    });
  });
}
