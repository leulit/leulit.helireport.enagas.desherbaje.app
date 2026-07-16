// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';

import 'package:helireport_desherbaje/core/result/data_result.dart';
import 'package:helireport_desherbaje/core/services/connectivity_service.dart';
import 'package:helireport_desherbaje/core/sync/engine/sync_engine.dart';
import 'package:helireport_desherbaje/data/model/mensaje_entity.dart';
import 'package:helireport_desherbaje/data/sync/imagen_local_store.dart';
import 'package:helireport_desherbaje/data/sync/mensaje_local_store.dart';
import 'package:helireport_desherbaje/data/sync/purge_synced_segmento_usecase.dart';
import 'package:helireport_desherbaje/data/sync/video_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/imagen_segmento_entity.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';
import 'package:helireport_desherbaje/domain/entities/video_segmento_entity.dart';
import 'package:helireport_desherbaje/domain/repository/auth_repository.dart';
import 'package:helireport_desherbaje/domain/usecases/get_segmentos_usecase.dart';
import 'package:helireport_desherbaje/presentation/forzar_envio/forzar_envio_controller.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class MockGetSegmentosUseCase extends Mock implements GetSegmentosUseCase {}

class MockSyncEngine extends Mock implements SyncEngine {}

class MockConnectivityService extends Mock implements ConnectivityService {}

class MockAuthRepository extends Mock implements AuthRepository {}

class MockPurgeUseCase extends Mock implements PurgeSyncedSegmentoUseCase {}

class MockImagenLocalStore extends Mock implements ImagenLocalStore {}

class MockVideoLocalStore extends Mock implements VideoLocalStore {}

class MockMensajeLocalStore extends Mock implements MensajeLocalStore {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

SegmentoEntity _seg({int? id, String? clientId}) {
  final s =
      SegmentoEntity(id, 1, TipoInstalacion.lineal, [], clientId: clientId);
  s.estado = EstadoActividad.finalizada;
  s.tipoActividad = TipoActividad.desherbajeSelectivo;
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

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late MockGetSegmentosUseCase mockUseCase;
  late MockSyncEngine mockEngine;
  late MockConnectivityService mockConnectivity;
  late MockAuthRepository mockAuthRepo;
  late MockPurgeUseCase mockPurge;
  late MockImagenLocalStore mockImagenStore;
  late MockVideoLocalStore mockVideoStore;
  late MockMensajeLocalStore mockMensajeStore;
  late ForzarEnvioController controller;

  setUpAll(() {
    registerFallbackValue(SegmentoEntity(null, 0, TipoInstalacion.lineal, []));
    registerFallbackValue(<SegmentoEntity>[]);
  });

  setUp(() {
    Get.reset();

    mockUseCase = MockGetSegmentosUseCase();
    mockEngine = MockSyncEngine();
    mockConnectivity = MockConnectivityService();
    mockAuthRepo = MockAuthRepository();
    mockPurge = MockPurgeUseCase();
    mockImagenStore = MockImagenLocalStore();
    mockVideoStore = MockVideoLocalStore();
    mockMensajeStore = MockMensajeLocalStore();

    when(() => mockUseCase.execute())
        .thenAnswer((_) async => const DataSuccess([]));

    // Scoped drain matcher: covers both per-type-scoped calls (onlyClientIds
    // set) and the global position drain (onlyClientIds null).
    when(() => mockEngine.drain(
          entityType: any(named: 'entityType'),
          onlyClientIds: any(named: 'onlyClientIds'),
        )).thenAnswer((_) async => const DrainSummary());

    when(() => mockAuthRepo.getCurrentUser()).thenAnswer((_) async => null);

    // Child stores empty by default → only the 'segmento' scope drains.
    when(() => mockImagenStore.findWhere(any(), any()))
        .thenAnswer((_) async => []);
    when(() => mockVideoStore.findWhere(any(), any()))
        .thenAnswer((_) async => []);
    when(() => mockMensajeStore.findWhere(any(), any()))
        .thenAnswer((_) async => []);

    when(() => mockPurge.purgeIfFullySynced(any())).thenAnswer(
        (_) async => const PurgeOutcome(status: PurgeStatus.keptUnsynced));
    when(() => mockPurge.readUnsyncedSets())
        .thenAnswer((_) async => _noneUnsynced);

    controller = ForzarEnvioController(
      mockUseCase,
      mockEngine,
      mockConnectivity,
      authRepository: mockAuthRepo,
      purgeUseCase: mockPurge,
      imagenStore: mockImagenStore,
      videoStore: mockVideoStore,
      mensajeStore: mockMensajeStore,
    );
    Get.put(controller);
  });

  tearDown(Get.reset);

  group('enviarCloud (un segmento)', () {
    test('(a) drena SOLO los tipos de ese segmento en orden vídeo→foto→mensaje→segmento',
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
            entityType: 'video', onlyClientIds: any(named: 'onlyClientIds')),
        () => mockEngine.drain(
            entityType: 'imagen', onlyClientIds: any(named: 'onlyClientIds')),
        () => mockEngine.drain(
            entityType: 'mensaje', onlyClientIds: any(named: 'onlyClientIds')),
        () => mockEngine.drain(
            entityType: 'segmento', onlyClientIds: any(named: 'onlyClientIds')),
      ]);
    });

    test('(a2) tipos sin jobs de ese segmento no se drenan', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      // Child stores empty (default) → solo 'segmento' se drena.
      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      verify(() => mockEngine.drain(
          entityType: 'segmento',
          onlyClientIds: any(named: 'onlyClientIds'))).called(1);
      verifyNever(() => mockEngine.drain(
          entityType: 'video', onlyClientIds: any(named: 'onlyClientIds')));
      verifyNever(() => mockEngine.drain(
          entityType: 'imagen', onlyClientIds: any(named: 'onlyClientIds')));
      verifyNever(() => mockEngine.drain(
          entityType: 'mensaje', onlyClientIds: any(named: 'onlyClientIds')));
    });

    test('(b) sin red no invoca drain y pone lastError', () async {
      when(() => mockConnectivity.isConnected).thenReturn(false);

      await controller.enviarCloud(_seg(id: 1, clientId: 'seg-1'));

      verifyNever(() => mockEngine.drain(
          entityType: any(named: 'entityType'),
          onlyClientIds: any(named: 'onlyClientIds')));
      expect(controller.lastError.value, isNotEmpty);
    });

    test('(d) rechazados/conflictos se exponen en lastDrainSummary', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockEngine.drain(
              entityType: 'segmento',
              onlyClientIds: any(named: 'onlyClientIds')))
          .thenAnswer((_) async => const DrainSummary(rejected: 1, conflicts: 2));

      await controller.enviarCloud(_seg(id: 10, clientId: 'seg-1'));

      expect(controller.lastDrainSummary.value?.rejected, 1);
      expect(controller.lastDrainSummary.value?.conflicts, 2);
    });

    test('(e) authExpired corta el envío del segmento (no drena tipos posteriores)',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockVideoStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_vid('vid-1')]);
      when(() => mockImagenStore.findWhere('segmento_client_id', any()))
          .thenAnswer((_) async => [_img('img-1')]);
      when(() => mockEngine.drain(
              entityType: 'video', onlyClientIds: any(named: 'onlyClientIds')))
          .thenAnswer((_) async => const DrainSummary(authExpired: true));

      await controller.enviarCloud(_seg(id: 5, clientId: 'seg-1'));

      verify(() => mockEngine.drain(
          entityType: 'video',
          onlyClientIds: any(named: 'onlyClientIds'))).called(1);
      verifyNever(() => mockEngine.drain(
          entityType: 'imagen', onlyClientIds: any(named: 'onlyClientIds')));
      verifyNever(() => mockEngine.drain(
          entityType: 'segmento', onlyClientIds: any(named: 'onlyClientIds')));
      // Invariante: nunca purgar tras authExpired.
      verifyNever(() => mockPurge.purgeIfFullySynced(any()));
    });

    test('(f) tras un drenado limpio invoca purgeIfFullySynced del segmento',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);

      await controller.enviarCloud(_seg(id: 42, clientId: 'seg-1'));

      verify(() => mockPurge.purgeIfFullySynced(any())).called(1);
    });
  });

  group('enviarAllCloud (todos)', () {
    test('(c) recorre segmentos pendientes y drena position una vez al final',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      final seg = _seg(id: 42, clientId: 'seg-1');
      controller.segmentos.assignAll([seg]);
      // El segmento está pendiente (su clientId en el set de no-sincronizados).
      when(() => mockPurge.readUnsyncedSets()).thenAnswer(
        (_) async => const UnsyncedSets(
            segmento: {'seg-1'}, imagen: {}, video: {}, mensaje: {}),
      );

      await controller.enviarAllCloud();

      verifyInOrder([
        () => mockEngine.drain(
            entityType: 'segmento', onlyClientIds: any(named: 'onlyClientIds')),
        () => mockEngine.drain(entityType: 'position'),
      ]);
    });

    test('segmentos ya sincronizados no se envían (no están pendientes)',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      controller.segmentos.assignAll([_seg(id: 42, clientId: 'seg-1')]);
      // readUnsyncedSets vacío (default) → segmento fully synced → no pendiente.

      await controller.enviarAllCloud();

      verifyNever(() => mockEngine.drain(
          entityType: 'segmento', onlyClientIds: any(named: 'onlyClientIds')));
      // position sí se drena siempre al final.
      verify(() => mockEngine.drain(entityType: 'position')).called(1);
    });

    test('sin red no invoca drain y pone lastError', () async {
      when(() => mockConnectivity.isConnected).thenReturn(false);

      await controller.enviarAllCloud();

      verifyNever(() => mockEngine.drain(
          entityType: any(named: 'entityType'),
          onlyClientIds: any(named: 'onlyClientIds')));
      expect(controller.lastError.value, isNotEmpty);
    });

    test('authExpired en un segmento corta el bucle: position no se drena',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      controller.segmentos.assignAll([_seg(id: 42, clientId: 'seg-1')]);
      when(() => mockPurge.readUnsyncedSets()).thenAnswer(
        (_) async => const UnsyncedSets(
            segmento: {'seg-1'}, imagen: {}, video: {}, mensaje: {}),
      );
      when(() => mockEngine.drain(
              entityType: 'segmento',
              onlyClientIds: any(named: 'onlyClientIds')))
          .thenAnswer((_) async => const DrainSummary(authExpired: true));

      await controller.enviarAllCloud();

      verifyNever(() => mockEngine.drain(entityType: 'position'));
      verifyNever(() => mockPurge.purgeIfFullySynced(any()));
    });

    test('summary combinado acumula totales de segmentos + position', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      controller.segmentos.assignAll([_seg(id: 42, clientId: 'seg-1')]);
      when(() => mockPurge.readUnsyncedSets()).thenAnswer(
        (_) async => const UnsyncedSets(
            segmento: {'seg-1'}, imagen: {}, video: {}, mensaje: {}),
      );
      when(() => mockEngine.drain(
              entityType: 'segmento',
              onlyClientIds: any(named: 'onlyClientIds')))
          .thenAnswer((_) async => const DrainSummary(succeeded: 2));
      when(() => mockEngine.drain(entityType: 'position'))
          .thenAnswer((_) async => const DrainSummary(conflicts: 1));

      await controller.enviarAllCloud();

      final s = controller.lastDrainSummary.value!;
      expect(s.succeeded, 2);
      expect(s.conflicts, 1);
    });
  });
}
