// Tests for VideoLocalStore.
// Covers: CREATE TABLE (incl. upload_offset), upsert/find, saveUploadOffset.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/data/sync/video_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/video_segmento_entity.dart';

Future<Database> _openDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  // singleInstance: false — otherwise sqflite_ffi caches connections by path
  // and reopening `inMemoryDatabasePath` within the same test run returns the
  // SAME underlying database, leaking schema state between tests.
  return openDatabase(inMemoryDatabasePath, version: 1, singleInstance: false);
}

VideoSegmentoEntity _vid({
  required String clientId,
  required int segmentoId,
  TipoVideo tipo = TipoVideo.antes,
  DateTime? capturadaAt,
  int uploadOffset = 0,
  String? segmentoClientId,
}) {
  final ts = capturadaAt ?? DateTime.utc(2026, 1, 1);
  return VideoSegmentoEntity(
    clientId: clientId,
    actividadId: 0,
    segmentoId: segmentoId,
    segmentoClientId: segmentoClientId,
    tipoVideo: tipo,
    filename: '$clientId.mp4',
    ruta: '/tmp/$clientId.mp4',
    capturadaAt: ts,
  )..uploadOffset = uploadOffset;
}

void main() {
  late Database db;
  late VideoLocalStore store;

  setUp(() async {
    db = await _openDb();
    store = VideoLocalStore(db);
    await store.migrate(db, 0, 2);
  });

  tearDown(() async => db.close());

  group('schema', () {
    test('entityType is video', () {
      expect(store.entityType, equals('video'));
    });

    test('schemaVersion is 2', () {
      expect(store.schemaVersion, equals(2));
    });

    test('upload_offset column exists after migration', () async {
      await db.insert('videos_segmento', {
        'client_id': 'schema-test',
        'segmento_id': 1,
        'tipo_video': 'antes',
        'filename': 'test.mp4',
        'ruta': '/tmp/test.mp4',
        'capturada_at': DateTime.utc(2026).toIso8601String(),
        'needs_sync': 1,
        'upload_offset': 0,
      });
      final rows = await db.query('videos_segmento',
          where: 'client_id = ?', whereArgs: ['schema-test']);
      expect(rows.first['upload_offset'], equals(0));
    });

    test('upload_id column exists after migration', () async {
      await db.insert('videos_segmento', {
        'client_id': 'schema-upload-id',
        'segmento_id': 1,
        'tipo_video': 'antes',
        'filename': 'test.mp4',
        'ruta': '/tmp/test.mp4',
        'capturada_at': DateTime.utc(2026).toIso8601String(),
        'needs_sync': 1,
        'upload_offset': 0,
        'upload_id': 'server-uuid-abc',
      });
      final rows = await db.query('videos_segmento',
          where: 'client_id = ?', whereArgs: ['schema-upload-id']);
      expect(rows.first['upload_id'], equals('server-uuid-abc'));
    });
  });

  group('upsert / findByClientId', () {
    test('upserted entity can be found by clientId', () async {
      final v = _vid(clientId: 'vid-a', segmentoId: 10);
      await store.upsert(v);

      final found = await store.findByClientId('vid-a');
      expect(found, isNotNull);
      expect(found!.clientId, equals('vid-a'));
      expect(found.segmentoId, equals(10));
    });

    test('findByClientId returns null for unknown id', () async {
      final found = await store.findByClientId('nonexistent');
      expect(found, isNull);
    });

    test('upsert replaces existing row', () async {
      final v = _vid(clientId: 'vid-b', segmentoId: 5);
      await store.upsert(v);

      final updated = _vid(clientId: 'vid-b', segmentoId: 5)
        ..tamanyoBytes = 99999;
      await store.upsert(updated);

      final found = await store.findByClientId('vid-b');
      expect(found!.tamanyoBytes, equals(99999));
    });
  });

  group('findWhere by segmento_id', () {
    test('returns videos for matching segmento_id', () async {
      await store.upsert(_vid(clientId: 'v1', segmentoId: 10));
      await store.upsert(_vid(clientId: 'v2', segmentoId: 10));
      await store.upsert(_vid(clientId: 'v3', segmentoId: 20));

      final result = await store.findWhere('segmento_id', 10);
      expect(result.length, equals(2));
      final ids = result.map((v) => v.clientId).toSet();
      expect(ids, containsAll(['v1', 'v2']));
    });

    test('returns empty list when no row matches', () async {
      await store.upsert(_vid(clientId: 'v-only', segmentoId: 1));
      final result = await store.findWhere('segmento_id', 999);
      expect(result, isEmpty);
    });

    test('order is capturada_at DESC', () async {
      final earlier = DateTime.utc(2026, 1, 1);
      final later = DateTime.utc(2026, 6, 1);

      await store.upsert(_vid(clientId: 'old', segmentoId: 5, capturadaAt: earlier));
      await store.upsert(_vid(clientId: 'new', segmentoId: 5, capturadaAt: later));

      final result = await store.findWhere('segmento_id', 5);
      expect(result.first.clientId, equals('new'));
      expect(result.last.clientId, equals('old'));
    });
  });

  group('saveUploadOffset', () {
    test('persists offset in upload_offset column', () async {
      final v = _vid(clientId: 'resume-a', segmentoId: 7, uploadOffset: 0);
      await store.upsert(v);

      await store.saveUploadOffset('resume-a', 5242880);

      final found = await store.findByClientId('resume-a');
      expect(found!.uploadOffset, equals(5242880));
    });

    test('successive saves update to latest offset', () async {
      final v = _vid(clientId: 'resume-b', segmentoId: 7, uploadOffset: 0);
      await store.upsert(v);

      await store.saveUploadOffset('resume-b', 1000000);
      await store.saveUploadOffset('resume-b', 2000000);

      final found = await store.findByClientId('resume-b');
      expect(found!.uploadOffset, equals(2000000));
    });
  });

  group('saveUploadId', () {
    test('persists upload_id after init', () async {
      final v = _vid(clientId: 'uid-a', segmentoId: 7);
      await store.upsert(v);

      await store.saveUploadId('uid-a', 'server-uuid-123');

      final found = await store.findByClientId('uid-a');
      expect(found!.uploadId, equals('server-uuid-123'));
    });

    test('overwrites previous upload_id on re-init', () async {
      final v = _vid(clientId: 'uid-b', segmentoId: 7);
      await store.upsert(v);

      await store.saveUploadId('uid-b', 'old-uuid');
      await store.saveUploadId('uid-b', 'new-uuid');

      final found = await store.findByClientId('uid-b');
      expect(found!.uploadId, equals('new-uuid'));
    });
  });

  group('markSynced', () {
    test('sets needs_sync=0 and integer remoteId → id column', () async {
      final v = _vid(clientId: 'sync-a', segmentoId: 3);
      await store.upsert(v);

      await store.markSynced(clientId: 'sync-a', remoteId: '42');

      final found = await store.findByClientId('sync-a');
      expect(found!.id, equals(42));
    });

    test('non-integer remoteId (UUID) → stored in upload_id column', () async {
      final v = _vid(clientId: 'sync-b', segmentoId: 3);
      await store.upsert(v);

      await store.markSynced(clientId: 'sync-b', remoteId: 'uuid-server-abc');

      final found = await store.findByClientId('sync-b');
      // id not set (not a parseable int)
      expect(found!.id, isNull);
      // upload_id is stored
      expect(found.uploadId, equals('uuid-server-abc'));
    });
  });

  group('delete', () {
    test('removes entity by clientId', () async {
      final v = _vid(clientId: 'del-a', segmentoId: 1);
      await store.upsert(v);
      await store.delete('del-a');

      final found = await store.findByClientId('del-a');
      expect(found, isNull);
    });
  });

  group('findByRemoteId (push-only stub)', () {
    test('always returns null', () async {
      final result = await store.findByRemoteId('123');
      expect(result, isNull);
    });
  });

  group('findWhere by segmento_client_id', () {
    test('returns videos for matching segmento_client_id', () async {
      await store.upsert(
          _vid(clientId: 'v-a', segmentoId: 0, segmentoClientId: 'seg-A'));
      await store.upsert(
          _vid(clientId: 'v-b', segmentoId: 0, segmentoClientId: 'seg-A'));
      await store.upsert(
          _vid(clientId: 'v-c', segmentoId: 0, segmentoClientId: 'seg-B'));

      final result = await store.findWhere('segmento_client_id', 'seg-A');
      expect(result.length, equals(2));
      final ids = result.map((v) => v.clientId).toSet();
      expect(ids, containsAll(['v-a', 'v-b']));
    });

    test('returns empty list when no row matches', () async {
      await store.upsert(_vid(
          clientId: 'v-x', segmentoId: 0, segmentoClientId: 'seg-known'));
      final result =
          await store.findWhere('segmento_client_id', 'seg-unknown');
      expect(result, isEmpty);
    });
  });

  group('stepwise migration 0→1→2', () {
    test('column is usable after migrating in two steps', () async {
      final freshDb = await _openDb();
      final freshStore = VideoLocalStore(freshDb);
      await freshStore.migrate(freshDb, 0, 1);
      await freshStore.migrate(freshDb, 1, 2);

      await freshStore.upsert(_vid(
          clientId: 'step-a', segmentoId: 0, segmentoClientId: 'seg-step'));
      final result =
          await freshStore.findWhere('segmento_client_id', 'seg-step');
      expect(result.length, equals(1));
      expect(result.first.clientId, equals('step-a'));

      await freshDb.close();
    });
  });
}
