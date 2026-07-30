// Tests de PendingEnvelopesQuery — sqflite_ffi real. Esta consulta ES el
// filtro de la pantalla "Forzar envío": si deja fuera un sobre con datos sin
// subir, el operario no tiene forma de enviarlo; si mete uno ya cerrado, la
// pantalla nunca se vacía.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/core/sync/contracts/sync_job.dart';
import 'package:helireport_desherbaje/core/sync/outbox/outbox_queue.dart';
import 'package:helireport_desherbaje/data/model/mensaje_entity.dart';
import 'package:helireport_desherbaje/data/sync/imagen_local_store.dart';
import 'package:helireport_desherbaje/data/sync/mensaje_local_store.dart';
import 'package:helireport_desherbaje/data/sync/pending_envelopes_query.dart';
import 'package:helireport_desherbaje/data/sync/segmento_local_store.dart';
import 'package:helireport_desherbaje/data/sync/video_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/imagen_segmento_entity.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';
import 'package:helireport_desherbaje/domain/entities/video_segmento_entity.dart';

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

SegmentoEntity _seg(String clientId, {int id = 42}) {
  final s = SegmentoEntity(id, 'CT1', TipoInstalacion.lineal, [],
      clientId: clientId);
  s.estado = EstadoActividad.ejecucion;
  s.descripcion = 'seg $clientId';
  return s;
}

ImagenSegmentoEntity _img(String clientId, String segClientId) =>
    ImagenSegmentoEntity(
      actividadId: 0,
      segmentoId: 42,
      segmentoClientId: segClientId,
      tipoFoto: TipoFoto.antes,
      filename: 'f',
      ruta: '/tmp/$clientId.jpg',
      capturadaAt: DateTime.utc(2025, 1, 1),
      clientId: clientId,
    );

VideoSegmentoEntity _vid(String clientId, String segClientId) =>
    VideoSegmentoEntity(
      actividadId: 0,
      segmentoId: 42,
      segmentoClientId: segClientId,
      tipoVideo: TipoVideo.antes,
      filename: 'v',
      ruta: '/tmp/$clientId.mp4',
      capturadaAt: DateTime.utc(2025, 1, 1),
      clientId: clientId,
    );

MensajeSegmentoEntity _msg(String clientId, String segClientId) =>
    MensajeSegmentoEntity(
      segmentoId: 42,
      segmentoClientId: segClientId,
      mensaje: 'm',
      clientId: clientId,
    );

void main() {
  late Database db;
  late SegmentoLocalStore segStore;
  late ImagenLocalStore imgStore;
  late VideoLocalStore vidStore;
  late MensajeLocalStore msgStore;
  late OutboxQueue outbox;
  late PendingEnvelopesQuery query;

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
        break;
      case SyncStatus.syncing:
        await outbox.markSyncing(id);
      case SyncStatus.synced:
        await outbox.markSynced(id, remoteId: '1');
      case SyncStatus.rejected:
        await outbox.markRejected(id, error: 'HTTP 400', statusCode: 400);
    }
  }

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await db.execute(_syncQueueDdl);

    segStore = SegmentoLocalStore(db);
    imgStore = ImagenLocalStore(db);
    vidStore = VideoLocalStore(db);
    msgStore = MensajeLocalStore(db);
    await segStore.migrate(db, 0, segStore.schemaVersion);
    await imgStore.migrate(db, 0, imgStore.schemaVersion);
    await vidStore.migrate(db, 0, vidStore.schemaVersion);
    await msgStore.migrate(db, 0, msgStore.schemaVersion);

    outbox = OutboxQueue(db);
    query = PendingEnvelopesQuery(db: db);
  });

  tearDown(() async => db.close());

  test('sin jobs → el sobre no aparece', () async {
    await segStore.upsert(_seg('seg-1'));

    expect(await query.read(), isEmpty);
  });

  test('cambio de estado sin enviar → aparece por "Datos"', () async {
    await segStore.upsert(_seg('seg-1'));
    await seedJob('segmento', 'seg-1', status: SyncStatus.pending);

    final out = await query.read();

    expect(out['seg-1']!.faltaSegmento, isTrue);
    expect(out['seg-1']!.tieneCosasQueSubir, isTrue);
    expect(out['seg-1']!.resumen, ['Datos']);
  });

  test('foto nueva en un segmento intacto → aparece solo por la foto',
      () async {
    await segStore.upsert(_seg('seg-1'));
    await seedJob('segmento', 'seg-1'); // ya entregado
    await segStore.markSyncConfirmed(
        'seg-1', DateTime.now().millisecondsSinceEpoch + 1000);
    await imgStore.upsert(_img('img-1', 'seg-1'));
    await seedJob('imagen', 'img-1', status: SyncStatus.pending);

    final out = await query.read();

    expect(out['seg-1']!.faltaSegmento, isFalse);
    expect(out['seg-1']!.faltaImagenes, 1);
    expect(out['seg-1']!.resumen, ['1 foto']);
  });

  test('todo entregado y cerrado → el sobre desaparece de la lista', () async {
    await segStore.upsert(_seg('seg-1'));
    await imgStore.upsert(_img('img-1', 'seg-1'));
    await vidStore.upsert(_vid('vid-1', 'seg-1'));
    await msgStore.upsert(_msg('msg-1', 'seg-1'));
    await seedJob('segmento', 'seg-1');
    await seedJob('imagen', 'img-1');
    await seedJob('video', 'vid-1');
    await seedJob('mensaje', 'msg-1');
    await segStore.markSyncConfirmed(
        'seg-1', DateTime.now().millisecondsSinceEpoch + 1000);

    expect(await query.read(), isEmpty);
  });

  // El agujero que tapaba el filtro por estado: todo subido, `sync-complete`
  // sin confirmar. Sin esta rama el sobre queda invisible y tapiado, y sus
  // filas siguen `pending` en backend hasta que un upsert las borre.
  test('todo entregado pero sin cerrar → aparece pidiendo cierre', () async {
    await segStore.upsert(_seg('seg-1'));
    await imgStore.upsert(_img('img-1', 'seg-1'));
    await seedJob('segmento', 'seg-1');
    await seedJob('imagen', 'img-1');
    // sync_confirmed_at sigue a null: nadie cerró.

    final out = await query.read();

    expect(out['seg-1']!.tieneCosasQueSubir, isFalse);
    expect(out['seg-1']!.necesitaCierre, isTrue);
    expect(out['seg-1']!.resumen, ['Falta confirmar el cierre']);
  });

  test('job rejected cuenta como pendiente (no como enviado)', () async {
    await segStore.upsert(_seg('seg-1'));
    await imgStore.upsert(_img('img-1', 'seg-1'));
    await seedJob('imagen', 'img-1', status: SyncStatus.rejected);

    final out = await query.read();

    expect(out['seg-1']!.faltaImagenes, 1);
  });

  test('un borrado pendiente no es dato de campo sin subir', () async {
    await segStore.upsert(_seg('seg-1'));
    await seedJob('segmento', 'seg-1',
        status: SyncStatus.pending, operation: SyncOperation.delete);

    expect(await query.read(), isEmpty);
  });

  test('cuenta cada tipo por separado y solo del sobre propio', () async {
    await segStore.upsert(_seg('seg-1'));
    await segStore.upsert(_seg('seg-2', id: 43));
    await imgStore.upsert(_img('img-1', 'seg-1'));
    await imgStore.upsert(_img('img-2', 'seg-1'));
    await msgStore.upsert(_msg('msg-1', 'seg-1'));
    await imgStore.upsert(_img('img-3', 'seg-2'));
    for (final id in ['img-1', 'img-2', 'img-3']) {
      await seedJob('imagen', id, status: SyncStatus.pending);
    }
    await seedJob('mensaje', 'msg-1', status: SyncStatus.pending);

    final out = await query.read();

    expect(out['seg-1']!.faltaImagenes, 2);
    expect(out['seg-1']!.faltaMensajes, 1);
    expect(out['seg-1']!.resumen, ['2 fotos', '1 mensaje']);
    expect(out['seg-2']!.faltaImagenes, 1);
  });
}
