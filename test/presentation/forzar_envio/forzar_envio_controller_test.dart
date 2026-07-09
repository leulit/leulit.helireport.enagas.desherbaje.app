// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';

import 'package:helireport_desherbaje/core/result/data_result.dart';
import 'package:helireport_desherbaje/core/services/connectivity_service.dart';
import 'package:helireport_desherbaje/core/sync/engine/sync_engine.dart';
import 'package:helireport_desherbaje/data/sync/purge_synced_segmento_usecase.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';
import 'package:helireport_desherbaje/domain/repository/auth_repository.dart';
import 'package:helireport_desherbaje/domain/usecases/get_segmentos_usecase.dart';
import 'package:helireport_desherbaje/presentation/forzar_envio/forzar_envio_controller.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class MockGetSegmentosUseCase extends Mock implements GetSegmentosUseCase {}

class MockSyncEngine extends Mock implements SyncEngine {}

class MockConnectivityService extends Mock implements ConnectivityService {}

class MockAuthRepository extends Mock implements AuthRepository {}

class MockPurgeUseCase extends Mock implements PurgeSyncedSegmentoUseCase {}

// ─── Helper ──────────────────────────────────────────────────────────────────

SegmentoEntity _fakeSegmento({int? id}) {
  final s = SegmentoEntity(id, 1, TipoInstalacion.lineal, []);
  s.estado = EstadoActividad.finalizada;
  s.tipoActividad = TipoActividad.desherbajeSelectivo;
  s.descripcion = 'Segmento test';
  return s;
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late MockGetSegmentosUseCase mockUseCase;
  late MockSyncEngine mockEngine;
  late MockConnectivityService mockConnectivity;
  late MockAuthRepository mockAuthRepo;
  late MockPurgeUseCase mockPurge;
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

    // Stub por defecto: lista vacía para no bloquear onInit.
    when(() => mockUseCase.execute())
        .thenAnswer((_) async => const DataSuccess([]));

    // Stub por defecto: engine ok vacío.
    when(() => mockEngine.drain(entityType: any(named: 'entityType')))
        .thenAnswer((_) async => const DrainSummary());

    // Stub por defecto: sin usuario autenticado.
    when(() => mockAuthRepo.getCurrentUser())
        .thenAnswer((_) async => null);

    // Stub por defecto: purga no borra nada (no-op inyectado).
    when(() => mockPurge.purgeIfFullySynced(any()))
        .thenAnswer(
            (_) async => const PurgeOutcome(status: PurgeStatus.keptUnsynced));
    when(() => mockPurge.purgeAllFullySynced(any()))
        .thenAnswer((_) async => const <PurgeOutcome>[]);

    controller = ForzarEnvioController(
      mockUseCase,
      mockEngine,
      mockConnectivity,
      authRepository: mockAuthRepo,
      purgeUseCase: mockPurge,
    );
    Get.put(controller);
  });

  tearDown(() {
    Get.reset();
  });

  // ─── (a) enviarCloud con red → drena segmento, imagen, mensaje ──────────

  group('enviarCloud', () {
    test('(a) con red invoca drain para segmento, imagen y mensaje en orden',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);

      final segmento = _fakeSegmento(id: 42);
      await controller.enviarCloud(segmento);

      verifyInOrder([
        () => mockEngine.drain(entityType: 'segmento'),
        () => mockEngine.drain(entityType: 'imagen'),
        () => mockEngine.drain(entityType: 'mensaje'),
      ]);
    });

    // ─── (b) sin red → NO invoca drain, pone lastError ────────────────────

    test('(b) sin red no invoca drain y pone lastError', () async {
      when(() => mockConnectivity.isConnected).thenReturn(false);

      await controller.enviarCloud(_fakeSegmento(id: 1));

      verifyNever(() => mockEngine.drain(entityType: any(named: 'entityType')));
      expect(controller.lastError.value, isNotEmpty);
    });

    // ─── (d) DrainSummary con rechazados/conflictos se refleja ────────────

    test('(d) summary con rechazados y conflictos se expone en lastDrainSummary',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);

      // segmento → rejected:1, imagen/mensaje → ok
      when(() => mockEngine.drain(entityType: 'segmento'))
          .thenAnswer((_) async => const DrainSummary(rejected: 1));
      when(() => mockEngine.drain(entityType: 'imagen'))
          .thenAnswer((_) async => const DrainSummary(conflicts: 2));
      when(() => mockEngine.drain(entityType: 'mensaje'))
          .thenAnswer((_) async => const DrainSummary());

      await controller.enviarCloud(_fakeSegmento(id: 10));

      expect(controller.lastDrainSummary.value?.rejected, 1);
      expect(controller.lastDrainSummary.value?.conflicts, 2);
    });

    // ─── (e) authExpired en primer drain → NO sigue con los siguientes ────

    test('(e) authExpired en segmento corta el bucle y no drena imagen ni mensaje',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);

      when(() => mockEngine.drain(entityType: 'segmento'))
          .thenAnswer((_) async => const DrainSummary(authExpired: true));

      await controller.enviarCloud(_fakeSegmento(id: 5));

      // El primer drain se llama...
      verify(() => mockEngine.drain(entityType: 'segmento')).called(1);
      // ...pero imagen y mensaje NO se llaman.
      verifyNever(() => mockEngine.drain(entityType: 'imagen'));
      verifyNever(() => mockEngine.drain(entityType: 'mensaje'));

      expect(controller.lastDrainSummary.value?.authExpired, isTrue);
    });

    // ─── (f) drenado limpio → purga el segmento enviado ───────────────────

    test('(f) tras un drenado limpio invoca purgeIfFullySynced del segmento',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);

      await controller.enviarCloud(_fakeSegmento(id: 42));

      verify(() => mockPurge.purgeIfFullySynced(any())).called(1);
    });

    // ─── (g) authExpired → NUNCA purga (invariante de seguridad) ──────────

    test('(g) authExpired en el drain NO purga el segmento', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockEngine.drain(entityType: 'segmento'))
          .thenAnswer((_) async => const DrainSummary(authExpired: true));

      await controller.enviarCloud(_fakeSegmento(id: 7));

      verifyNever(() => mockPurge.purgeIfFullySynced(any()));
    });
  });

  // ─── (c) enviarAllCloud drena todos los tipos ──────────────────────────────

  group('enviarAllCloud', () {
    test('(c) con red invoca drain para segmento, imagen, mensaje y position',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);

      await controller.enviarAllCloud();

      verifyInOrder([
        () => mockEngine.drain(entityType: 'segmento'),
        () => mockEngine.drain(entityType: 'imagen'),
        () => mockEngine.drain(entityType: 'mensaje'),
        () => mockEngine.drain(entityType: 'position'),
      ]);
    });

    test('sin red no invoca drain y pone lastError', () async {
      when(() => mockConnectivity.isConnected).thenReturn(false);

      await controller.enviarAllCloud();

      verifyNever(() => mockEngine.drain(entityType: any(named: 'entityType')));
      expect(controller.lastError.value, isNotEmpty);
    });

    test('authExpired en imagen corta el bucle: mensaje y position no se drenan',
        () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);

      when(() => mockEngine.drain(entityType: 'segmento'))
          .thenAnswer((_) async => const DrainSummary(succeeded: 1));
      when(() => mockEngine.drain(entityType: 'imagen'))
          .thenAnswer((_) async => const DrainSummary(authExpired: true));

      await controller.enviarAllCloud();

      verify(() => mockEngine.drain(entityType: 'segmento')).called(1);
      verify(() => mockEngine.drain(entityType: 'imagen')).called(1);
      verifyNever(() => mockEngine.drain(entityType: 'mensaje'));
      verifyNever(() => mockEngine.drain(entityType: 'position'));
      // Invariante: nunca purgar en lote tras un authExpired.
      verifyNever(() => mockPurge.purgeAllFullySynced(any()));
    });

    test('tras un drenado limpio invoca purgeAllFullySynced una vez', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);

      await controller.enviarAllCloud();

      verify(() => mockPurge.purgeAllFullySynced(any())).called(1);
    });

    test('summary combinado acumula totales de todos los tipos', () async {
      when(() => mockConnectivity.isConnected).thenReturn(true);

      when(() => mockEngine.drain(entityType: 'segmento'))
          .thenAnswer((_) async => const DrainSummary(succeeded: 2));
      when(() => mockEngine.drain(entityType: 'imagen'))
          .thenAnswer((_) async => const DrainSummary(succeeded: 1, retryable: 1));
      when(() => mockEngine.drain(entityType: 'mensaje'))
          .thenAnswer((_) async => const DrainSummary(rejected: 1));
      when(() => mockEngine.drain(entityType: 'position'))
          .thenAnswer((_) async => const DrainSummary(conflicts: 1));

      await controller.enviarAllCloud();

      final s = controller.lastDrainSummary.value!;
      expect(s.succeeded, 3);
      expect(s.retryable, 1);
      expect(s.rejected, 1);
      expect(s.conflicts, 1);
    });
  });
}
