// Tests for PurgeSyncedSegmentoUseCase — real sqflite_ffi DB, injected fake
// file deleter. Verifies:
//  1. a fully-synced segment + its image+video+message are purged (rows, outbox
//     jobs, and files);
//  2. a segment with ANY unsynced dependent is left COMPLETELY intact;
//  3. no-remote-id short-circuit;
//  4. atomic rollback when a mid-cascade delete throws;
//  5. batch purge purges only the fully-synced segment;
//  6. the pure isFullySynced predicate.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/core/sync/contracts/sync_job.dart';
import 'package:helireport_desherbaje/core/sync/outbox/outbox_queue.dart';
import 'package:helireport_desherbaje/data/model/mensaje_entity.dart';
import 'package:helireport_desherbaje/data/network/network_response.dart';
import 'package:helireport_desherbaje/data/network/network_service.dart';
import 'package:helireport_desherbaje/data/sync/imagen_local_store.dart';
import 'package:helireport_desherbaje/data/sync/mensaje_local_store.dart';
import 'package:helireport_desherbaje/data/sync/purge_synced_segmento_usecase.dart';
import 'package:helireport_desherbaje/data/sync/segmento_local_store.dart';
import 'package:helireport_desherbaje/data/sync/video_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/imagen_segmento_entity.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';
import 'package:helireport_desherbaje/domain/entities/video_segmento_entity.dart';

class _MockNetwork extends Mock implements NetworkService {}

const _syncQueueDdl = '''
  CREATE TABLE sync_queue (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type  TEXT    NOT NULL,
    client_id    TEXT    NOT NULL,
    operation    TEXT    NOT NULL,
    status       TEXT    NOT NULL DEFAULT 'pending',
    attempts     INTEGER NOT NULL DEFAULT 0,
    last_error   TEXT,
    status_code  INTEGER,
    remote_id    TEXT,
    created_at   INTEGER NOT NULL,
    synced_at    INTEGER,
    UNIQUE(entity_type, client_id, operation)
  )
''';

/// A MensajeLocalStore whose delete throws for one clientId — used to force a
/// mid-transaction failure and assert rollback.
class _ThrowingMensajeStore extends MensajeLocalStore {
  final String badClientId;
  _ThrowingMensajeStore(super.db, this.badClientId);

  @override
  Future<void> delete(String clientId, {DatabaseExecutor? txn}) async {
    if (clientId == badClientId) throw StateError('boom');
    return super.delete(clientId, txn: txn);
  }
}

SegmentoEntity _seg({required String clientId, int? id}) {
  final s =
      SegmentoEntity(id, 'CT1', TipoInstalacion.lineal, [], clientId: clientId);
  s.estado = EstadoActividad.finalizada;
  s.descripcion = 'seg $clientId';
  return s;
}

ImagenSegmentoEntity _img({
  required String clientId,
  required String segmentoClientId,
  required String ruta,
}) =>
    ImagenSegmentoEntity(
      clientId: clientId,
      actividadId: 0,
      segmentoId: 0,
      segmentoClientId: segmentoClientId,
      tipoFoto: TipoFoto.antes,
      filename: '$clientId.jpg',
      ruta: ruta,
      capturadaAt: DateTime.utc(2025, 1, 1),
    );

VideoSegmentoEntity _vid({
  required String clientId,
  required String segmentoClientId,
  required String ruta,
}) =>
    VideoSegmentoEntity(
      clientId: clientId,
      actividadId: 0,
      segmentoId: 0,
      segmentoClientId: segmentoClientId,
      tipoVideo: TipoVideo.antes,
      filename: '$clientId.mp4',
      ruta: ruta,
      capturadaAt: DateTime.utc(2025, 1, 1),
    );

MensajeSegmentoEntity _msg({
  required String clientId,
  required int segmentoId,
  String? segmentoClientId,
}) =>
    MensajeSegmentoEntity(
      clientId: clientId,
      segmentoId: segmentoId,
      segmentoClientId: segmentoClientId,
      mensaje: 'm $clientId',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SegmentoLocalStore segStore;
  late ImagenLocalStore imgStore;
  late VideoLocalStore vidStore;
  late MensajeLocalStore msgStore;
  late OutboxQueue outbox;
  late List<String> deletedPaths;
  late _MockNetwork network;

  Future<void> seedJob(
    String entityType,
    String clientId, {
    SyncStatus status = SyncStatus.synced,
    SyncOperation operation = SyncOperation.create,
  }) async {
    final id = await outbox.enqueue(
      entityType: entityType,
      clientId: clientId,
      operation: operation,
    );
    switch (status) {
      case SyncStatus.pending:
        break; // enqueue leaves it pending
      case SyncStatus.syncing:
        await outbox.markSyncing(id);
      case SyncStatus.synced:
        await outbox.markSynced(id, remoteId: '1');
      case SyncStatus.rejected:
        await outbox.markRejected(id, error: 'x');
    }
  }

  Future<int> queueRowCount() async {
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM sync_queue');
    return (r.first['c'] as int?) ?? 0;
  }

  PurgeSyncedSegmentoUseCase buildUseCase({MensajeLocalStore? mensajeStore}) =>
      PurgeSyncedSegmentoUseCase(
        db: db,
        segmentoStore: segStore,
        imagenStore: imgStore,
        videoStore: vidStore,
        mensajeStore: mensajeStore ?? msgStore,
        outbox: outbox,
        deleteFile: (p) async => deletedPaths.add(p),
        network: network,
      );

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await db.execute(_syncQueueDdl);

    segStore = SegmentoLocalStore(db);
    imgStore = ImagenLocalStore(db);
    vidStore = VideoLocalStore(db);
    msgStore = MensajeLocalStore(db);
    await segStore.migrate(db, 0, 2);
    await imgStore.migrate(db, 0, 3);
    await vidStore.migrate(db, 0, 3);
    await msgStore.migrate(db, 0, msgStore.schemaVersion);

    outbox = OutboxQueue(db);
    deletedPaths = <String>[];

    // sync-complete succeeds by default.
    network = _MockNetwork();
    when(() => network.post(
          any(),
          body: any(named: 'body'),
          headers: any(named: 'headers'),
        )).thenAnswer(
      (_) async => NetworkResponse<dynamic>(statusCode: 200, data: null),
    );
  });

  tearDown(() async => db.close());

  group('purgeIfFullySynced', () {
    test('fully-synced segment → row + dependents + files all purged', () async {
      final seg = _seg(clientId: 'seg-1', id: 42);
      await segStore.upsert(seg);
      await imgStore.upsert(
          _img(clientId: 'img-1', segmentoClientId: 'seg-1', ruta: '/tmp/img1.jpg'));
      await imgStore.upsert(
          _img(clientId: 'img-2', segmentoClientId: 'seg-1', ruta: '/tmp/img2.jpg'));
      await vidStore.upsert(
          _vid(clientId: 'vid-1', segmentoClientId: 'seg-1', ruta: '/tmp/vid1.mp4'));
      await msgStore
          .upsert(_msg(clientId: 'msg-1', segmentoId: 42, segmentoClientId: 'seg-1'));

      await seedJob('segmento', 'seg-1');
      await seedJob('imagen', 'img-1');
      await seedJob('imagen', 'img-2');
      await seedJob('video', 'vid-1');
      await seedJob('mensaje', 'msg-1');

      final outcome = await buildUseCase().purgeIfFullySynced(seg);

      expect(outcome.status, PurgeStatus.purged);
      expect(outcome.imagenes, 2);
      expect(outcome.videos, 1);
      expect(outcome.mensajes, 1);

      expect(await segStore.findByClientId('seg-1'), isNull);
      expect(await imgStore.findByClientId('img-1'), isNull);
      expect(await imgStore.findByClientId('img-2'), isNull);
      expect(await vidStore.findByClientId('vid-1'), isNull);
      expect(await msgStore.findBySegmento(42), isEmpty);

      // All outbox jobs for the purged entities are gone.
      expect(await queueRowCount(), 0);

      // Exactly the two image files + one video file were deleted.
      expect(deletedPaths.toSet(),
          {'/tmp/img1.jpg', '/tmp/img2.jpg', '/tmp/vid1.mp4'});
      expect(deletedPaths.length, 3);
    });

    test('fires sync-complete (POST /sync-complete) before purging', () async {
      final seg = _seg(clientId: 'seg-1', id: 42);
      await segStore.upsert(seg);
      await seedJob('segmento', 'seg-1');

      final outcome = await buildUseCase().purgeIfFullySynced(seg);

      expect(outcome.status, PurgeStatus.purged);
      final captured = verify(() => network.post(
            captureAny(),
            body: captureAny(named: 'body'),
            headers: captureAny(named: 'headers'),
          )).captured;
      expect(captured[0] as String, contains('/segmentos/42/sync-complete'));
      // §7: sin body — el id viaja en el path. §1: el HMAC es la única auth,
      // no hay Bearer.
      expect(captured[1], isNull);
      expect(captured[2], isNull);
    });

    test('sync-complete failure → finalizeFailed, nothing deleted', () async {
      when(() => network.post(
            any(),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
          )).thenAnswer(
        (_) async => NetworkResponse<dynamic>(statusCode: 500, data: null),
      );

      final seg = _seg(clientId: 'seg-1', id: 42);
      await segStore.upsert(seg);
      await imgStore.upsert(
          _img(clientId: 'img-1', segmentoClientId: 'seg-1', ruta: '/tmp/img1.jpg'));
      await seedJob('segmento', 'seg-1');
      await seedJob('imagen', 'img-1');

      final outcome = await buildUseCase().purgeIfFullySynced(seg);

      expect(outcome.status, PurgeStatus.finalizeFailed);
      // Nothing deleted; kept for the next send.
      expect(await segStore.findByClientId('seg-1'), isNotNull);
      expect(await imgStore.findByClientId('img-1'), isNotNull);
      expect(await queueRowCount(), 2);
      expect(deletedPaths, isEmpty);
    });

    test('sync-complete HTTP 200 + body {ok:false} → finalizeFailed, nada borrado',
        () async {
      when(() => network.post(
            any(),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
          )).thenAnswer(
        (_) async => NetworkResponse<dynamic>(
          statusCode: 200,
          data: {'ok': false, 'error': 'segmento bloqueado'},
        ),
      );

      final seg = _seg(clientId: 'seg-1', id: 42);
      await segStore.upsert(seg);
      await imgStore.upsert(
          _img(clientId: 'img-1', segmentoClientId: 'seg-1', ruta: '/tmp/img1.jpg'));
      await seedJob('segmento', 'seg-1');
      await seedJob('imagen', 'img-1');

      final outcome = await buildUseCase().purgeIfFullySynced(seg);

      expect(outcome.status, PurgeStatus.finalizeFailed);
      expect(await segStore.findByClientId('seg-1'), isNotNull);
      expect(await imgStore.findByClientId('img-1'), isNotNull);
      expect(await queueRowCount(), 2);
      expect(deletedPaths, isEmpty);
    });

    // (2) A segment with ANY unsynced dependent must be left COMPLETELY intact.
    for (final offender in const [
      ('imagen img-1 pending', 'imagen', 'img-1', SyncStatus.pending),
      ('video vid-1 pending', 'video', 'vid-1', SyncStatus.pending),
      ('video vid-1 syncing', 'video', 'vid-1', SyncStatus.syncing),
      ('mensaje msg-1 rejected', 'mensaje', 'msg-1', SyncStatus.rejected),
      ('segmento seg-1 pending', 'segmento', 'seg-1', SyncStatus.pending),
    ]) {
      final (label, type, clientId, status) = offender;
      test('unsynced dependent ($label) → nothing deleted, all intact', () async {
        final seg = _seg(clientId: 'seg-1', id: 42);
        await segStore.upsert(seg);
        await imgStore.upsert(
            _img(clientId: 'img-1', segmentoClientId: 'seg-1', ruta: '/tmp/img1.jpg'));
        await vidStore.upsert(
            _vid(clientId: 'vid-1', segmentoClientId: 'seg-1', ruta: '/tmp/vid1.mp4'));
        await msgStore
          .upsert(_msg(clientId: 'msg-1', segmentoId: 42, segmentoClientId: 'seg-1'));

        // Every entity gets a job; the offender's is in a non-synced state.
        await seedJob('segmento', 'seg-1',
            status: type == 'segmento' && clientId == 'seg-1'
                ? status
                : SyncStatus.synced);
        await seedJob('imagen', 'img-1',
            status: type == 'imagen' ? status : SyncStatus.synced);
        await seedJob('video', 'vid-1',
            status: type == 'video' ? status : SyncStatus.synced);
        await seedJob('mensaje', 'msg-1',
            status: type == 'mensaje' ? status : SyncStatus.synced);

        final outcome = await buildUseCase().purgeIfFullySynced(seg);

        expect(outcome.status, PurgeStatus.keptUnsynced);
        // ALL rows still present.
        expect(await segStore.findByClientId('seg-1'), isNotNull);
        expect(await imgStore.findByClientId('img-1'), isNotNull);
        expect(await vidStore.findByClientId('vid-1'), isNotNull);
        expect(await msgStore.findBySegmento(42), isNotEmpty);
        // No outbox rows removed (4 jobs still there).
        expect(await queueRowCount(), 4);
        // No files deleted.
        expect(deletedPaths, isEmpty);
      });
    }

    test('segment with no remote id → skipped, nothing deleted', () async {
      final seg = _seg(clientId: 'seg-noid', id: null);
      await segStore.upsert(seg);

      final outcome = await buildUseCase().purgeIfFullySynced(seg);

      expect(outcome.status, PurgeStatus.skippedNoRemoteId);
      expect(await segStore.findByClientId('seg-noid'), isNotNull);
      expect(deletedPaths, isEmpty);
    });

    test('mid-cascade delete throws → full rollback, nothing lost', () async {
      final seg = _seg(clientId: 'seg-1', id: 42);
      await segStore.upsert(seg);
      await imgStore.upsert(
          _img(clientId: 'img-1', segmentoClientId: 'seg-1', ruta: '/tmp/img1.jpg'));
      await vidStore.upsert(
          _vid(clientId: 'vid-1', segmentoClientId: 'seg-1', ruta: '/tmp/vid1.mp4'));
      await msgStore
          .upsert(_msg(clientId: 'msg-1', segmentoId: 42, segmentoClientId: 'seg-1'));

      await seedJob('segmento', 'seg-1');
      await seedJob('imagen', 'img-1');
      await seedJob('video', 'vid-1');
      await seedJob('mensaje', 'msg-1');

      final throwingStore = _ThrowingMensajeStore(db, 'msg-1');
      final useCase = buildUseCase(mensajeStore: throwingStore);

      await expectLater(useCase.purgeIfFullySynced(seg), throwsA(isA<StateError>()));

      // Rollback: every row and every outbox job survive.
      expect(await segStore.findByClientId('seg-1'), isNotNull);
      expect(await imgStore.findByClientId('img-1'), isNotNull);
      expect(await vidStore.findByClientId('vid-1'), isNotNull);
      expect(await msgStore.findBySegmento(42), isNotEmpty);
      expect(await queueRowCount(), 4);
      expect(deletedPaths, isEmpty);
    });
  });

  group('purgeAllFullySynced', () {
    test('purges only the fully-synced segment; leaves the other intact',
        () async {
      final seg1 = _seg(clientId: 'seg-1', id: 42);
      final seg2 = _seg(clientId: 'seg-2', id: 43);
      await segStore.upsert(seg1);
      await segStore.upsert(seg2);
      // seg-1: fully synced.
      await imgStore.upsert(
          _img(clientId: 'img-1', segmentoClientId: 'seg-1', ruta: '/tmp/img1.jpg'));
      await seedJob('segmento', 'seg-1');
      await seedJob('imagen', 'img-1');
      // seg-2: has a pending image → must be kept.
      await imgStore.upsert(
          _img(clientId: 'img-2b', segmentoClientId: 'seg-2', ruta: '/tmp/img2b.jpg'));
      await seedJob('segmento', 'seg-2');
      await seedJob('imagen', 'img-2b', status: SyncStatus.pending);

      final outcomes =
          await buildUseCase().purgeAllFullySynced([seg1, seg2]);

      expect(outcomes[0].status, PurgeStatus.purged);
      expect(outcomes[1].status, PurgeStatus.keptUnsynced);

      expect(await segStore.findByClientId('seg-1'), isNull);
      expect(await imgStore.findByClientId('img-1'), isNull);
      expect(await segStore.findByClientId('seg-2'), isNotNull);
      expect(await imgStore.findByClientId('img-2b'), isNotNull);
      expect(deletedPaths, {'/tmp/img1.jpg'});
    });

    // Finding 1 (data-loss): a media row captured AFTER the batch started but
    // BEFORE its segment is reached must NOT be purged. The batch must read the
    // unsynced sets fresh per segment (never a single pre-loop snapshot).
    test('media captured mid-batch is observed → its segment is kept', () async {
      final seg1 = _seg(clientId: 'seg-1', id: 42);
      final seg2 = _seg(clientId: 'seg-2', id: 43);
      await segStore.upsert(seg1);
      await segStore.upsert(seg2);
      // Both segments look fully synced at the start of the batch.
      await imgStore.upsert(
          _img(clientId: 'img-1', segmentoClientId: 'seg-1', ruta: '/tmp/img1.jpg'));
      await imgStore.upsert(
          _img(clientId: 'img-2', segmentoClientId: 'seg-2', ruta: '/tmp/img2.jpg'));
      await seedJob('segmento', 'seg-1');
      await seedJob('imagen', 'img-1');
      await seedJob('segmento', 'seg-2');
      await seedJob('imagen', 'img-2');

      // While seg-1 is being purged (its file delete runs mid-batch), the
      // operator captures a new photo for seg-2 with a PENDING upload job.
      var injected = false;
      final useCase = PurgeSyncedSegmentoUseCase(
        db: db,
        segmentoStore: segStore,
        imagenStore: imgStore,
        videoStore: vidStore,
        mensajeStore: msgStore,
        outbox: outbox,
        network: network,
        deleteFile: (p) async {
          if (injected) return;
          injected = true;
          await imgStore.upsert(_img(
              clientId: 'img-2new',
              segmentoClientId: 'seg-2',
              ruta: '/tmp/img2new.jpg'));
          await seedJob('imagen', 'img-2new', status: SyncStatus.pending);
        },
      );

      final outcomes = await useCase.purgeAllFullySynced([seg1, seg2]);

      expect(outcomes[0].status, PurgeStatus.purged);
      // seg-2 kept: its freshly captured photo is still pending upload.
      expect(outcomes[1].status, PurgeStatus.keptUnsynced);
      expect(await segStore.findByClientId('seg-2'), isNotNull);
      expect(await imgStore.findByClientId('img-2'), isNotNull);
      expect(await imgStore.findByClientId('img-2new'), isNotNull);
    });
  });

  group('isFullySynced (pure predicate)', () {
    final seg = _seg(clientId: 'S', id: 1);
    final imgs = [
      _img(clientId: 'I', segmentoClientId: 'S', ruta: 'i'),
    ];
    final vids = [
      _vid(clientId: 'V', segmentoClientId: 'S', ruta: 'v'),
    ];
    final msgs = [_msg(clientId: 'M', segmentoId: 1)];

    UnsyncedSets sets({
      Set<String> segmento = const {},
      Set<String> imagen = const {},
      Set<String> video = const {},
      Set<String> mensaje = const {},
    }) =>
        UnsyncedSets(
          segmento: segmento,
          imagen: imagen,
          video: video,
          mensaje: mensaje,
        );

    test('all clean → true', () {
      expect(
        PurgeSyncedSegmentoUseCase.isFullySynced(seg, imgs, vids, msgs, sets()),
        isTrue,
      );
    });

    test('segment in set → false', () {
      expect(
        PurgeSyncedSegmentoUseCase.isFullySynced(
            seg, imgs, vids, msgs, sets(segmento: {'S'})),
        isFalse,
      );
    });

    test('image in set → false', () {
      expect(
        PurgeSyncedSegmentoUseCase.isFullySynced(
            seg, imgs, vids, msgs, sets(imagen: {'I'})),
        isFalse,
      );
    });

    test('video in set → false', () {
      expect(
        PurgeSyncedSegmentoUseCase.isFullySynced(
            seg, imgs, vids, msgs, sets(video: {'V'})),
        isFalse,
      );
    });

    test('message in set → false', () {
      expect(
        PurgeSyncedSegmentoUseCase.isFullySynced(
            seg, imgs, vids, msgs, sets(mensaje: {'M'})),
        isFalse,
      );
    });
  });
}
