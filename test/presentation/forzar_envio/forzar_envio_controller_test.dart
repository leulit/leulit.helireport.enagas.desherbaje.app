// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';

import 'package:helireport_desherbaje/core/result/data_result.dart';
import 'package:helireport_desherbaje/core/services/connectivity_service.dart';
import 'package:helireport_desherbaje/core/sync/contracts/sync_job.dart';
import 'package:helireport_desherbaje/core/sync/engine/sync_engine.dart';
import 'package:helireport_desherbaje/core/sync/outbox/outbox_queue.dart';
import 'package:helireport_desherbaje/core/sync/pull/cancel_token.dart';
import 'package:helireport_desherbaje/data/model/mensaje_entity.dart';
import 'package:helireport_desherbaje/data/sync/imagen_local_store.dart';
import 'package:helireport_desherbaje/data/sync/mensaje_local_store.dart';
import 'package:helireport_desherbaje/data/sync/pending_envelopes_query.dart';
import 'package:helireport_desherbaje/data/sync/propagate_segmento_remote_id_usecase.dart';
import 'package:helireport_desherbaje/data/sync/purge_synced_segmento_usecase.dart';
import 'package:helireport_desherbaje/data/sync/segmento_local_store.dart';
import 'package:helireport_desherbaje/data/sync/traza_local_store.dart';
import 'package:helireport_desherbaje/data/sync/video_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/imagen_segmento_entity.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';
import 'package:helireport_desherbaje/domain/entities/video_segmento_entity.dart';
import 'package:helireport_desherbaje/domain/usecases/get_segmentos_usecase.dart';
import 'package:helireport_desherbaje/presentation/forzar_envio/forzar_envio_controller.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class MockGetSegmentosUseCase extends Mock implements GetSegmentosUseCase {}

class MockSyncEngine extends Mock implements SyncEngine {}

class MockConnectivityService extends Mock implements ConnectivityService {}

class MockPurgeUseCase extends Mock implements PurgeSyncedSegmentoUseCase {}

class MockImagenLocalStore extends Mock implements ImagenLocalStore {}

class MockVideoLocalStore extends Mock implements VideoLocalStore {}

class MockMensajeLocalStore extends Mock implements MensajeLocalStore {}

class MockSegmentoLocalStore extends Mock implements SegmentoLocalStore {}

class MockTrazaLocalStore extends Mock implements TrazaLocalStore {}

class MockPropagateSegmentoRemoteIdUseCase extends Mock
    implements PropagateSegmentoRemoteIdUseCase {}

class MockOutboxQueue extends Mock implements OutboxQueue {}

class MockPendingEnvelopesQuery extends Mock implements PendingEnvelopesQuery {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

SegmentoEntity _seg({int? id, String? clientId}) {
  final s =
      SegmentoEntity(id, 'CT1', TipoInstalacion.lineal, [], clientId: clientId);
  s.estado = EstadoActividad.finalizada;
  s.tipoActividad = TipoActividad.posicionDesherbajeTraza;
  s.descripcion = 'Segmento test';
  return s;
}

ImagenSegmentoEntity _img(String clientId) => ImagenSegmentoEntity(
      actividadId: 0,
      segmentoId: 0,
      tipoFoto: TipoFoto.antes,
      filename: 'i',
      ruta: '',
      capturadaAt: DateTime.utc(2025, 1, 1),
      clientId: clientId,
    );

VideoSegmentoEntity _vid(String clientId) => VideoSegmentoEntity(
      actividadId: 0,
      segmentoId: 0,
      tipoVideo: TipoVideo.antes,
      filename: 'v',
      ruta: '',
      capturadaAt: DateTime.utc(2025, 1, 1),
      clientId: clientId,
    );

MensajeSegmentoEntity _msg(String clientId) =>
    MensajeSegmentoEntity(segmentoId: 0, mensaje: 'm', clientId: clientId);

const _noneUnsynced =
    UnsyncedSets(segmento: {}, imagen: {}, video: {}, mensaje: {});

SyncJob _rejected({
  required int id,
  required String entityType,
  required String clientId,
  SyncOperation operation = SyncOperation.create,
}) =>
    SyncJob(
      id: id,
      entityType: entityType,
      clientId: clientId,
      operation: operation,
      status: SyncStatus.rejected,
      attempts: 1,
      createdAt: DateTime.utc(2025, 1, 1),
      lastError: 'HTTP 400',
      statusCode: 400,
    );

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late MockGetSegmentosUseCase mockUseCase;
  late MockSyncEngine mockEngine;
  late MockConnectivityService mockConnectivity;
  late MockPurgeUseCase mockPurge;
  late MockImagenLocalStore mockImagenStore;
  late MockVideoLocalStore mockVideoStore;
  late MockMensajeLocalStore mockMensajeStore;
  late MockSegmentoLocalStore mockSegmentoStore;
  late MockPropagateSegmentoRemoteIdUseCase mockPropagate;
  late MockOutboxQueue mockOutbox;
  late MockTrazaLocalStore mockTrazaStore;
  late MockPendingEnvelopesQuery mockPendingQuery;
  late ForzarEnvioController controller;

  // Siembra la lista como lo haría `loadSegmentos`: `filtradas` se deriva de
  // `segmentos` aplicando los filtros activos (aquí, ninguno). `enviarAllCloud`
  // recorre `filtradas`, no `segmentos`: lo que se ve es lo que se envía.
  void seed(List<SegmentoEntity> list) {
    controller.segmentos.assignAll(list);
    controller.filterByEstado(null);
  }

  setUpAll(() {
    registerFallbackValue(SegmentoEntity(null, '', TipoInstalacion.lineal, []));
    registerFallbackValue(<SegmentoEntity>[]);
    registerFallbackValue(SyncOperation.create);
  });

  setUp(() {
    Get.reset();

    mockUseCase = MockGetSegmentosUseCase();
    mockEngine = MockSyncEngine();
    mockConnectivity = MockConnectivityService();
    mockPurge = MockPurgeUseCase();
    mockImagenStore = MockImagenLocalStore();
    mockVideoStore = MockVideoLocalStore();
    mockMensajeStore = MockMensajeLocalStore();
    mockSegmentoStore = MockSegmentoLocalStore();
    mockPropagate = MockPropagateSegmentoRemoteIdUseCase();
    mockOutbox = MockOutboxQueue();
    mockTrazaStore = MockTrazaLocalStore();
    mockPendingQuery = MockPendingEnvelopesQuery();

    when(() => mockTrazaStore.deleteSynced()).thenAnswer((_) async => 0);
    when(() => mockPendingQuery.read()).thenAnswer((_) async => {});

    // Por defecto NADA está subido-sin-confirmar: el sobre anterior cerró bien.
    // Es el caso normal y el que prueba que no se reenvía lo ya confirmado.
    when(() => mockPurge.unconfirmedChildIds(
          segmentoClientId: any(named: 'segmentoClientId'),
          entityType: any(named: 'entityType'),
          candidatos: any(named: 'candidatos'),
        )).thenAnswer((_) async => const <String>{});

    when(() => mockOutbox.enqueue(
          entityType: any(named: 'entityType'),
          clientId: any(named: 'clientId'),
          operation: any(named: 'operation'),
        )).thenAnswer((_) async => 1);

    // Por defecto no hay nada atascado en `rejected`: cada test que lo necesite
    // lo sobrescribe.
    when(() => mockOutbox.rejectedJobs(entityType: any(named: 'entityType')))
        .thenAnswer((_) async => []);

    when(() => mockUseCase.execute())
        .thenAnswer((_) async => const DataSuccess([]));

    // Scoped drain matcher: covers both per-type-scoped calls (onlyClientIds
    // set) and the global position drain (onlyClientIds null).
    when(() => mockEngine.drain(
            entityType: any(named: 'entityType'),
            onlyClientIds: any(named: 'onlyClientIds'),
            token: any(named: 'token'),
            onProgress: any(named: 'onProgress')))
        .thenAnswer((_) async => const DrainSummary());

    // Child stores empty by default → only the 'segmento' scope drains.
    when(() => mockImagenStore.findWhere(any(), any()))
        .thenAnswer((_) async => []);
    when(() => mockVideoStore.findWhere(any(), any()))
        .thenAnswer((_) async => []);
    when(() => mockMensajeStore.findWhere(any(), any()))
        .thenAnswer((_) async => []);
    when(() => mockVideoStore.clearUploadSessions(any()))
        .thenAnswer((_) async {});

    when(() => mockPurge.purgeIfFullySynced(any())).thenAnswer(
        (_) async => const PurgeOutcome(status: PurgeStatus.keptUnsynced));
    when(() => mockPurge.readUnsyncedSets())
        .thenAnswer((_) async => _noneUnsynced);

    // El segmento upsert deja el id remoto en el store local; por defecto
    // devolvemos el segmento ya con id (42) para que _sendOne pueda propagar
    // y continuar con los hijos.
    when(() => mockSegmentoStore.findByClientId(any()))
        .thenAnswer((_) async => _seg(id: 42, clientId: 'seg-1'));
    when(() => mockPropagate.propagate(any(), any())).thenAnswer((_) async {});

    controller = ForzarEnvioController(
      mockUseCase,
      mockEngine,
      mockConnectivity,
      purgeUseCase: mockPurge,
      imagenStore: mockImagenStore,
      videoStore: mockVideoStore,
      mensajeStore: mockMensajeStore,
      segmentoStore: mockSegmentoStore,
      propagate: mockPropagate,
      outbox: mockOutbox,
      trazaStore: mockTrazaStore,
      pendingQuery: mockPendingQuery,
    );
    Get.put(controller);
  });

  tearDown(Get.reset);

  group('enviarCloud (un segmento)', () {
    test(
        '(a) drena SOLO los tipos de ese segmento en orden segmento→vídeo→foto→mensaje',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockVideoStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_vid('vid-1')]);
      when(() => mockImagenStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_img('img-1')]);
      when(() => mockMensajeStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_msg('msg-1')]);

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      verifyInOrder([
        () => mockEngine.drain(
            entityType: 'segmento',
            onlyClientIds: any(named: 'onlyClientIds'),
            token: any(named: 'token'),
            onProgress: any(named: 'onProgress')),
        () => mockEngine.drain(
            entityType: 'video',
            onlyClientIds: any(named: 'onlyClientIds'),
            token: any(named: 'token'),
            onProgress: any(named: 'onProgress')),
        () => mockEngine.drain(
            entityType: 'imagen',
            onlyClientIds: any(named: 'onlyClientIds'),
            token: any(named: 'token'),
            onProgress: any(named: 'onProgress')),
        () => mockEngine.drain(
            entityType: 'mensaje',
            onlyClientIds: any(named: 'onlyClientIds'),
            token: any(named: 'token'),
            onProgress: any(named: 'onProgress')),
      ]);
      // El id remoto del segmento se propaga a los hijos ANTES de drenarlos.
      verify(() => mockPropagate.propagate('seg-1', 42)).called(1);
    });

    test('(a2) tipos sin jobs de ese segmento no se drenan', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      // Child stores empty (default) → solo 'segmento' se drena.
      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      verify(() => mockEngine.drain(
          entityType: 'segmento',
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress'))).called(1);
      verifyNever(() => mockEngine.drain(
          entityType: 'video',
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress')));
      verifyNever(() => mockEngine.drain(
          entityType: 'imagen',
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress')));
      verifyNever(() => mockEngine.drain(
          entityType: 'mensaje',
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress')));
    });

    // Un upsert entregado borra en backend lo que ese segmento tenga en
    // `estadotransmision='pending'`, es decir lo que subió en un intento que
    // ningún sync-complete cerró. Eso —y solo eso— hay que reenviarlo.
    test('(a3) upsert entregado → reencola lo subido SIN confirmar', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockEngine.drain(
              entityType: 'segmento',
              onlyClientIds: any(named: 'onlyClientIds'),
              token: any(named: 'token'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const DrainSummary(succeeded: 1));
      when(() => mockVideoStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_vid('vid-1')]);
      when(() => mockImagenStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_img('img-1')]);
      when(() => mockMensajeStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_msg('msg-1')]);
      when(() => mockPurge.unconfirmedChildIds(
            segmentoClientId: any(named: 'segmentoClientId'),
            entityType: 'video',
            candidatos: any(named: 'candidatos'),
          )).thenAnswer((_) async => const {'vid-1'});
      when(() => mockPurge.unconfirmedChildIds(
            segmentoClientId: any(named: 'segmentoClientId'),
            entityType: 'imagen',
            candidatos: any(named: 'candidatos'),
          )).thenAnswer((_) async => const {'img-1'});
      when(() => mockPurge.unconfirmedChildIds(
            segmentoClientId: any(named: 'segmentoClientId'),
            entityType: 'mensaje',
            candidatos: any(named: 'candidatos'),
          )).thenAnswer((_) async => const {'msg-1'});

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      verify(() => mockOutbox.enqueue(
          entityType: 'video',
          clientId: 'vid-1',
          operation: SyncOperation.create)).called(1);
      verify(() => mockOutbox.enqueue(
          entityType: 'imagen',
          clientId: 'img-1',
          operation: SyncOperation.create)).called(1);
      verify(() => mockOutbox.enqueue(
          entityType: 'mensaje',
          clientId: 'msg-1',
          operation: SyncOperation.create)).called(1);
    });

    // REGRESIÓN — duplicación de media en nube. Fotos/vídeos/mensajes cerrados
    // por un sync-complete anterior están `complete` en backend y sobreviven al
    // upsert. Reenviarlos los duplica: la API ya no deduplica por client_id.
    // Caso real: subo dos fotos hoy, mañana paso el segmento a `finalizada` y
    // el upsert de ese cambio no debe resubir nada.
    test('(a3b) hijos ya confirmados → NO se reencolan aunque salga upsert',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockEngine.drain(
              entityType: 'segmento',
              onlyClientIds: any(named: 'onlyClientIds'),
              token: any(named: 'token'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const DrainSummary(succeeded: 1));
      when(() => mockVideoStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_vid('vid-1')]);
      when(() => mockImagenStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_img('img-1')]);
      when(() => mockMensajeStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_msg('msg-1')]);
      // `unconfirmedChildIds` vacío por defecto: todo cerrado en el envío previo.

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      verifyNever(() => mockOutbox.enqueue(
            entityType: any(named: 'entityType'),
            clientId: any(named: 'clientId'),
            operation: any(named: 'operation'),
          ));
      verifyNever(() => mockVideoStore.clearUploadSessions(any()));
    });

    test('(a4) upsert NO entregado → no reencola nada', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockEngine.drain(
              entityType: 'segmento',
              onlyClientIds: any(named: 'onlyClientIds'),
              token: any(named: 'token'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const DrainSummary(retryable: 1));
      when(() => mockVideoStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_vid('vid-1')]);
      when(() => mockImagenStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_img('img-1')]);

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      verifyNever(() => mockOutbox.enqueue(
            entityType: any(named: 'entityType'),
            clientId: any(named: 'clientId'),
            operation: any(named: 'operation'),
          ));
    });

    // BLOCKER — pérdida total de un vídeo de campo. El upsert entregado anula
    // el intento anterior en el backend y borra sus ficheros `pending` (§2
    // regla 2). Si la sesión de subida guardada sobrevive, el adapter reanuda
    // contra ella, lee `complete: true`, devuelve SyncSuccess sin subir un byte,
    // y el sync-complete posterior purga el vídeo local: deja de existir en
    // ambos lados.
    test('(a5) upsert entregado → descarta las sesiones de subida de vídeo',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockEngine.drain(
              entityType: 'segmento',
              onlyClientIds: any(named: 'onlyClientIds'),
              token: any(named: 'token'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const DrainSummary(succeeded: 1));
      when(() => mockVideoStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_vid('vid-1')]);

      when(() => mockPurge.unconfirmedChildIds(
            segmentoClientId: any(named: 'segmentoClientId'),
            entityType: 'video',
            candidatos: any(named: 'candidatos'),
          )).thenAnswer((_) async => const {'vid-1'});

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      verify(() => mockVideoStore.clearUploadSessions('seg-1')).called(1);
    });

    test('(a5b) las sesiones se descartan ANTES de drenar los vídeos',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockEngine.drain(
              entityType: 'segmento',
              onlyClientIds: any(named: 'onlyClientIds'),
              token: any(named: 'token'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const DrainSummary(succeeded: 1));
      when(() => mockVideoStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_vid('vid-1')]);

      when(() => mockPurge.unconfirmedChildIds(
            segmentoClientId: any(named: 'segmentoClientId'),
            entityType: 'video',
            candidatos: any(named: 'candidatos'),
          )).thenAnswer((_) async => const {'vid-1'});

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      // Si se limpiaran después, el adapter ya habría corrido con el uploadId
      // muerto y el borrado no serviría de nada.
      verifyInOrder([
        () => mockVideoStore.clearUploadSessions('seg-1'),
        () => mockEngine.drain(
            entityType: 'video',
            onlyClientIds: any(named: 'onlyClientIds'),
            token: any(named: 'token'),
            onProgress: any(named: 'onProgress')),
      ]);
    });

    test(
        '(a6) upsert NO entregado → NO descarta sesiones (no resubir en balde)',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockEngine.drain(
              entityType: 'segmento',
              onlyClientIds: any(named: 'onlyClientIds'),
              token: any(named: 'token'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const DrainSummary());
      when(() => mockVideoStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_vid('vid-1')]);

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      // Sin upsert entregado no hay intento anulado: la sesión sigue viva y su
      // reanudación es legítima.
      verifyNever(() => mockVideoStore.clearUploadSessions(any()));
    });

    test('(i) finalizeFailed se reporta en lastError (no es éxito silencioso)',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockPurge.purgeIfFullySynced(any())).thenAnswer(
          (_) async => const PurgeOutcome(status: PurgeStatus.finalizeFailed));

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      expect(controller.lastError.value, isNotEmpty);
    });

    test('(i2) purgado limpio no ensucia lastError', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockPurge.purgeIfFullySynced(any())).thenAnswer(
          (_) async => const PurgeOutcome(status: PurgeStatus.purged));

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      expect(controller.lastError.value, isEmpty);
    });

    test('(b) sin red no invoca drain y pone lastError', () async {
      when(() => mockConnectivity.isConnected).thenReturn(false);

      await controller.enviarCloud(_seg(id: 1, clientId: 'seg-1'));

      verifyNever(() => mockEngine.drain(
          entityType: any(named: 'entityType'),
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress')));
      expect(controller.lastError.value, isNotEmpty);
    });

    test('(d) rechazados/conflictos se exponen en lastDrainSummary', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockEngine.drain(
              entityType: 'segmento',
              onlyClientIds: any(named: 'onlyClientIds'),
              token: any(named: 'token'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer(
              (_) async => const DrainSummary(rejected: 1, conflicts: 2));

      await controller.enviarCloud(_seg(id: 10, clientId: 'seg-1'));

      expect(controller.lastDrainSummary.value?.rejected, 1);
      expect(controller.lastDrainSummary.value?.conflicts, 2);
    });

    test(
        '(e) authExpired corta el envío del segmento (no drena tipos posteriores)',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockVideoStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_vid('vid-1')]);
      when(() => mockImagenStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_img('img-1')]);
      when(() => mockEngine.drain(
              entityType: 'video',
              onlyClientIds: any(named: 'onlyClientIds'),
              token: any(named: 'token'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const DrainSummary(authExpired: true));

      await controller.enviarCloud(_seg(id: 5, clientId: 'seg-1'));

      // El segmento sí se drena primero (limpio); el authExpired llega al
      // drenar los vídeos y corta ahí — imagen ya no se drena.
      verify(() => mockEngine.drain(
          entityType: 'segmento',
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress'))).called(1);
      verify(() => mockEngine.drain(
          entityType: 'video',
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress'))).called(1);
      verifyNever(() => mockEngine.drain(
          entityType: 'imagen',
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress')));
      // Invariante: nunca purgar tras authExpired.
      verifyNever(() => mockPurge.purgeIfFullySynced(any()));
    });

    test('(f) tras un drenado limpio invoca purgeIfFullySynced del segmento',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      verify(() => mockPurge.purgeIfFullySynced(any())).called(1);
    });

    test(
        '(g) si el segmento no sincroniza limpio (rejected>0) no toca hijos ni propaga',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockEngine.drain(
              entityType: 'segmento',
              onlyClientIds: any(named: 'onlyClientIds'),
              token: any(named: 'token'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const DrainSummary(rejected: 1));

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      verifyNever(() => mockPropagate.propagate(any(), any()));
      verifyNever(() => mockEngine.drain(
          entityType: 'video',
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress')));
      verifyNever(() => mockEngine.drain(
          entityType: 'imagen',
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress')));
      verifyNever(() => mockEngine.drain(
          entityType: 'mensaje',
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress')));
      verifyNever(() => mockPurge.purgeIfFullySynced(any()));
    });

    test(
        '(h) sin id de backend tras el upsert (defensivo) no propaga ni continúa',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockSegmentoStore.findByClientId(any()))
          .thenAnswer((_) async => _seg(id: null, clientId: 'seg-1'));

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      verifyNever(() => mockPropagate.propagate(any(), any()));
      verifyNever(() => mockEngine.drain(
          entityType: 'video',
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress')));
      verifyNever(() => mockPurge.purgeIfFullySynced(any()));
    });
  });

  // Un job `rejected` es invisible para `nextPending` (solo lee `pending`) pero
  // SÍ cuenta como no-sincronizado para la purga: sin desatascarlo, el sobre
  // queda bloqueado para siempre y en silencio.
  group('desatasco de jobs rejected', () {
    test('(r1) un job rejected del sobre vuelve a pending (re-enqueue)',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockVideoStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_vid('vid-1')]);
      when(() => mockOutbox.rejectedJobs(entityType: 'video')).thenAnswer(
          (_) async =>
              [_rejected(id: 7, entityType: 'video', clientId: 'vid-1')]);

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      verify(() => mockOutbox.enqueue(
            entityType: 'video',
            clientId: 'vid-1',
            operation: SyncOperation.create,
          )).called(greaterThanOrEqualTo(1));
    });

    test('(r2) el desatasco ocurre ANTES del drain (si no, el drain no lo ve)',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockOutbox.rejectedJobs(entityType: 'segmento')).thenAnswer(
          (_) async =>
              [_rejected(id: 1, entityType: 'segmento', clientId: 'seg-1')]);

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      verifyInOrder([
        () => mockOutbox.enqueue(
              entityType: 'segmento',
              clientId: 'seg-1',
              operation: SyncOperation.create,
            ),
        () => mockEngine.drain(
            entityType: 'segmento',
            onlyClientIds: any(named: 'onlyClientIds'),
            token: any(named: 'token'),
            onProgress: any(named: 'onProgress')),
      ]);
    });

    test('(r3) un job rejected de OTRO segmento NO se toca', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockVideoStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_vid('vid-1')]);
      // El outbox devuelve rechazados de dos sobres distintos; solo 'vid-1'
      // pertenece al que se está enviando.
      when(() => mockOutbox.rejectedJobs(entityType: 'video'))
          .thenAnswer((_) async => [
                _rejected(id: 7, entityType: 'video', clientId: 'vid-1'),
                _rejected(id: 8, entityType: 'video', clientId: 'vid-otro'),
              ]);
      when(() => mockOutbox.rejectedJobs(entityType: 'segmento'))
          .thenAnswer((_) async => [
                _rejected(id: 9, entityType: 'segmento', clientId: 'seg-otro'),
              ]);

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      verifyNever(() => mockOutbox.enqueue(
            entityType: any(named: 'entityType'),
            clientId: 'vid-otro',
            operation: any(named: 'operation'),
          ));
      verifyNever(() => mockOutbox.enqueue(
            entityType: any(named: 'entityType'),
            clientId: 'seg-otro',
            operation: any(named: 'operation'),
          ));
    });

    test('(r4) se respeta la operación original del job, no siempre create',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockOutbox.rejectedJobs(entityType: 'segmento'))
          .thenAnswer((_) async => [
                _rejected(
                  id: 1,
                  entityType: 'segmento',
                  clientId: 'seg-1',
                  operation: SyncOperation.update,
                ),
              ]);

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      verify(() => mockOutbox.enqueue(
            entityType: 'segmento',
            clientId: 'seg-1',
            operation: SyncOperation.update,
          )).called(1);
    });

    test('(r5) si tras el envío el sobre sigue bloqueado, lastError lo dice',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockVideoStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_vid('vid-1')]);
      // El job vuelve a fallar: sigue en `rejected` en la segunda consulta.
      when(() => mockOutbox.rejectedJobs(entityType: 'video')).thenAnswer(
          (_) async =>
              [_rejected(id: 7, entityType: 'video', clientId: 'vid-1')]);

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      expect(controller.lastError.value, contains('vídeos'));
      expect(controller.lastInfo.value, isEmpty);
    });

    test('(r6) envío limpio sin nada pendiente deja un info distinguible',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      expect(controller.lastError.value, isEmpty);
      expect(controller.lastInfo.value, isNotEmpty);
    });
  });

  group('enviarAllCloud (todos)', () {
    test('(c) recorre segmentos pendientes y drena position una vez al final',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      final seg = _seg(id: 42, clientId: 'seg-1');
      seed([seg]);
      // El segmento está pendiente (su clientId en el set de no-sincronizados).
      when(() => mockPurge.readUnsyncedSets()).thenAnswer(
        (_) async => const UnsyncedSets(
            segmento: {'seg-1'}, imagen: {}, video: {}, mensaje: {}),
      );

      await controller.enviarAllCloud();

      verifyInOrder([
        () => mockEngine.drain(
            entityType: 'segmento',
            onlyClientIds: any(named: 'onlyClientIds'),
            token: any(named: 'token'),
            onProgress: any(named: 'onProgress')),
        () => mockEngine.drain(
            entityType: 'traza',
            token: any(named: 'token'),
            onProgress: any(named: 'onProgress')),
      ]);
    });

    test('lista vacía: no se drena ningún segmento, la traza sí', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      // `PendingEnvelopesQuery` no devuelve nada → nada que enviar. La decisión
      // de qué está pendiente vive AHÍ, no en `enviarAllCloud`.

      await controller.enviarAllCloud();

      verifyNever(() => mockEngine.drain(
          entityType: 'segmento',
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress')));
      // El GPS es global, no cuelga de ningún segmento: se drena igualmente.
      verify(() => mockEngine.drain(
          entityType: 'traza',
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress'))).called(1);
    });

    // MAJOR — un segmento en `finalizeFailed` (todo subido, solo cayó el POST de
    // sync-complete) tiene CERO jobs sin sincronizar, así que un filtro por
    // "no totalmente sincronizado" lo excluye para siempre: sus filas se quedan
    // `pending` en el backend y el próximo upsert las borra.
    test('segmento en finalizeFailed se reintenta y re-POSTea sync-complete',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      seed([_seg(id: 42, clientId: 'seg-1')]);
      // Todo sincronizado (readUnsyncedSets vacío por defecto): si sigue en
      // local es que el cierre nunca se confirmó — el 200 lo habría purgado.
      when(() => mockPurge.purgeIfFullySynced(any())).thenAnswer(
          (_) async => const PurgeOutcome(status: PurgeStatus.finalizeFailed));

      await controller.enviarAllCloud();

      verify(() => mockEngine.drain(
          entityType: 'segmento',
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress'))).called(1);
      verify(() => mockPurge.purgeIfFullySynced(any())).called(1);
      expect(controller.lastError.value, isNotEmpty);
    });

    test('reintento de cierre puro no descarta sesiones de vídeo', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      seed([_seg(id: 42, clientId: 'seg-1')]);
      when(() => mockVideoStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_vid('vid-1')]);
      // Drain del segmento sin entregas (succeeded 0): el upsert ya estaba
      // `synced`, no se anula ningún intento → nada que resubir.
      when(() => mockPurge.purgeIfFullySynced(any())).thenAnswer(
          (_) async => const PurgeOutcome(status: PurgeStatus.finalizeFailed));

      await controller.enviarAllCloud();

      verifyNever(() => mockVideoStore.clearUploadSessions(any()));
      verifyNever(() => mockOutbox.enqueue(
            entityType: any(named: 'entityType'),
            clientId: any(named: 'clientId'),
            operation: any(named: 'operation'),
          ));
    });

    test('sin red no invoca drain y pone lastError', () async {
      when(() => mockConnectivity.isConnected).thenReturn(false);

      await controller.enviarAllCloud();

      verifyNever(() => mockEngine.drain(
          entityType: any(named: 'entityType'),
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress')));
      expect(controller.lastError.value, isNotEmpty);
    });

    test('authExpired en un segmento corta el bucle: position no se drena',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      seed([_seg(id: 42, clientId: 'seg-1')]);
      when(() => mockPurge.readUnsyncedSets()).thenAnswer(
        (_) async => const UnsyncedSets(
            segmento: {'seg-1'}, imagen: {}, video: {}, mensaje: {}),
      );
      when(() => mockEngine.drain(
              entityType: 'segmento',
              onlyClientIds: any(named: 'onlyClientIds'),
              token: any(named: 'token'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const DrainSummary(authExpired: true));

      await controller.enviarAllCloud();

      verifyNever(() => mockEngine.drain(
          entityType: 'traza',
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress')));
      verifyNever(() => mockPurge.purgeIfFullySynced(any()));
    });

    test('summary combinado acumula totales de segmentos + position', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      seed([_seg(id: 42, clientId: 'seg-1')]);
      when(() => mockPurge.readUnsyncedSets()).thenAnswer(
        (_) async => const UnsyncedSets(
            segmento: {'seg-1'}, imagen: {}, video: {}, mensaje: {}),
      );
      when(() => mockEngine.drain(
              entityType: 'segmento',
              onlyClientIds: any(named: 'onlyClientIds'),
              token: any(named: 'token'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const DrainSummary(succeeded: 2));
      when(() => mockEngine.drain(
              entityType: 'traza',
              token: any(named: 'token'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const DrainSummary(conflicts: 1));

      await controller.enviarAllCloud();

      final s = controller.lastDrainSummary.value!;
      expect(s.succeeded, 2);
      expect(s.conflicts, 1);
    });
  });

  group('cancelación', () {
    test('cancelarEnvio sin envío en curso no hace nada', () {
      controller.cancelarEnvio();
      expect(controller.isCancelando.value, isFalse);
    });

    test('el token viaja a drain y se cancela al pulsar', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      CancelToken? capturado;
      when(() => mockEngine.drain(
          entityType: any(named: 'entityType'),
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress'))).thenAnswer((inv) async {
        capturado = inv.namedArguments[#token] as CancelToken?;
        // El usuario pulsa "Cancelar" mientras el primer drain está en vuelo.
        controller.cancelarEnvio();
        return const DrainSummary(succeeded: 1);
      });

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      expect(capturado, isNotNull);
      expect(capturado!.isCancelled, isTrue);
      // El estado se limpia al terminar: si no, los botones quedarían
      // congelados en "Cancelando…" para siempre.
      expect(controller.isCancelando.value, isFalse);
      expect(controller.enviandoIds, isEmpty);
      expect(controller.isEnviando, isFalse);
    });

    test('cancelado a media tanda: no arranca el siguiente segmento ni traza',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      seed([
        _seg(id: 42, clientId: 'seg-1'),
        _seg(id: 43, clientId: 'seg-2'),
      ]);
      when(() => mockPurge.readUnsyncedSets()).thenAnswer(
        (_) async => const UnsyncedSets(
            segmento: {'seg-1', 'seg-2'}, imagen: {}, video: {}, mensaje: {}),
      );
      // El primer drain de segmento devuelve "cancelado".
      when(() => mockEngine.drain(
              entityType: 'segmento',
              onlyClientIds: any(named: 'onlyClientIds'),
              token: any(named: 'token'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const DrainSummary(cancelled: true));

      await controller.enviarAllCloud();

      verify(() => mockEngine.drain(
          entityType: 'segmento',
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress'))).called(1);
      verifyNever(() => mockEngine.drain(
          entityType: 'traza',
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress')));
      expect(controller.lastDrainSummary.value!.cancelled, isTrue);
      // Cancelar no es error: se informa, no se alarma.
      expect(controller.lastError.value, isEmpty);
      expect(controller.lastInfo.value, contains('cancelado'));
      expect(controller.isEnviandoTodos.value, isFalse);
    });

    test('progresoEnvio se publica durante el envío y se limpia al terminar',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      seed([
        _seg(id: 42, clientId: 'seg-1'),
        _seg(id: 43, clientId: 'seg-2'),
      ]);
      when(() => mockPurge.readUnsyncedSets()).thenAnswer(
        (_) async => const UnsyncedSets(
            segmento: {'seg-1', 'seg-2'}, imagen: {}, video: {}, mensaje: {}),
      );
      final vistos = <String>[];
      when(() => mockEngine.drain(
          entityType: any(named: 'entityType'),
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress'))).thenAnswer((_) async {
        vistos.add(controller.progresoEnvio.value);
        return const DrainSummary();
      });

      await controller.enviarAllCloud();

      expect(vistos.any((v) => v.startsWith('Enviando 1 de 2')), isTrue);
      expect(vistos.any((v) => v.startsWith('Enviando 2 de 2')), isTrue);
      // Sin limpiar, la barra se quedaría colgada tras el envío.
      expect(controller.progresoEnvio.value, isEmpty);
    });

    test('envío individual y masivo son mutuamente excluyentes', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      controller.enviandoIds.add('seg-1');

      await controller.enviarAllCloud();

      verifyNever(() => mockEngine.drain(
          entityType: any(named: 'entityType'),
          onlyClientIds: any(named: 'onlyClientIds'),
          token: any(named: 'token'),
          onProgress: any(named: 'onProgress')));
    });
  });
}
