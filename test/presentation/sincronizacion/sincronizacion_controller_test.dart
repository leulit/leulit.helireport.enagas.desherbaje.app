// Tests for SincronizacionController — WS5 (NF-12, NF-13, NF-14, NF-15).
//
// Coverage:
//   (1) reload lanza → fila error, lastDownloadAt NO avanza (NF-12)
//   (2) reload → cache → success pero servedFromCache==true, timestamp NO
//       avanza (NF-14)
//   (3) reload → network → success, servedFromCache==false, timestamp avanza
//       + persiste (NF-14 inverso)
//   (4) descargar antes de _initRows (rows vacío) no lanza StateError, no-op
//       (NF-15)
//   (5) cancelar() durante descargarTodo pasa token cancelado a reload (NF-13)
//
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:helireport_desherbaje/core/services/connectivity_service.dart';
import 'package:helireport_desherbaje/core/services/gasoductos_service.dart';
import 'package:helireport_desherbaje/core/services/hitos_service.dart';
import 'package:helireport_desherbaje/core/services/master_data_load_result.dart';
import 'package:helireport_desherbaje/core/services/pks_service.dart';
import 'package:helireport_desherbaje/core/sync/offline_module.dart';
import 'package:helireport_desherbaje/core/sync/outbox/outbox_queue.dart';
import 'package:helireport_desherbaje/core/sync/pull/cancel_token.dart';
import 'package:helireport_desherbaje/domain/repository/auth_repository.dart';
import 'package:helireport_desherbaje/presentation/sincronizacion/sincronizacion_controller.dart';
import 'package:helireport_desherbaje/presentation/sincronizacion/sync_models.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class MockConnectivityService extends Mock implements ConnectivityService {}

class MockGasoductosService extends Mock implements GasoductosService {}

class MockPksService extends Mock implements PksService {}

class MockHitosService extends Mock implements HitosService {}

class MockOutboxQueue extends Mock implements OutboxQueue {}

class MockAuthRepository extends Mock implements AuthRepository {}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late MockConnectivityService mockConnectivity;
  late MockGasoductosService mockGasoductos;
  late MockPksService mockPks;
  late MockHitosService mockHitos;
  late MockOutboxQueue mockOutbox;
  late MockAuthRepository mockAuth;
  late SincronizacionController controller;

  setUp(() async {
    Get.reset();
    await DI.reset();
    SharedPreferences.setMockInitialValues({});

    mockConnectivity = MockConnectivityService();
    mockGasoductos = MockGasoductosService();
    mockPks = MockPksService();
    mockHitos = MockHitosService();
    mockOutbox = MockOutboxQueue();
    mockAuth = MockAuthRepository();

    when(() => mockConnectivity.isConnected).thenReturn(true);
    when(() => mockOutbox.countPending(entityType: any(named: 'entityType')))
        .thenAnswer((_) async => 0);

    // Stub observable fields required by _attachProgressWorkers.
    when(() => mockGasoductos.totalFiles).thenReturn(RxInt(0));
    when(() => mockGasoductos.processedFiles).thenReturn(RxInt(0));
    when(() => mockPks.totalFiles).thenReturn(RxInt(0));
    when(() => mockPks.processedFiles).thenReturn(RxInt(0));
    when(() => mockHitos.totalFiles).thenReturn(RxInt(0));
    when(() => mockHitos.processedFiles).thenReturn(RxInt(0));

    DI.registerSingleton<OutboxQueue>(mockOutbox);
    OfflineModule.resetPullRunners();

    controller = SincronizacionController(
      authRepository: mockAuth,
      gasoductosService: mockGasoductos,
      pksService: mockPks,
      hitosService: mockHitos,
      connectivity: mockConnectivity,
    );
    Get.put(controller);

    // Wait for _initRows to complete.
    await Future.delayed(Duration.zero);
  });

  tearDown(() async {
    OfflineModule.resetPullRunners();
    Get.reset();
    await DI.reset();
  });

  // ─── (1) NF-12: reload throws → row error, lastDownloadAt unchanged ─────

  test(
    '(1) NF-12: gasoductos reload lanza → fila error, lastDownloadAt no avanza',
    () async {
      when(() => mockGasoductos.reload(token: any(named: 'token')))
          .thenThrow(Exception('servidor caído'));

      final before = controller.rows
          .firstWhere((r) => r.kind == MasterDataKind.gasoductos)
          .lastDownloadAt;

      await controller.descargar(MasterDataKind.gasoductos);

      final row = controller.rows
          .firstWhere((r) => r.kind == MasterDataKind.gasoductos);
      expect(row.status, equals(MasterDataStatus.error));
      expect(row.errorMessage, isNotNull);
      expect(row.lastDownloadAt, equals(before));

      // SharedPreferences must NOT have been written.
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey('sync_master_last_download_gasoductos'),
        isFalse,
      );
    },
  );

  // ─── (2) NF-14: reload → cache → servedFromCache=true, no timestamp ──────

  test(
    '(2) NF-14: gasoductos reload cache → success con servedFromCache=true, timestamp no avanza',
    () async {
      when(() => mockGasoductos.reload(token: any(named: 'token')))
          .thenAnswer(
            (_) async => const MasterDataLoadResult(MasterDataSource.cache, 5),
          );

      await controller.descargar(MasterDataKind.gasoductos);

      final row = controller.rows
          .firstWhere((r) => r.kind == MasterDataKind.gasoductos);
      expect(row.status, equals(MasterDataStatus.success));
      expect(row.servedFromCache, isTrue);
      expect(row.lastDownloadAt, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey('sync_master_last_download_gasoductos'),
        isFalse,
      );
    },
  );

  // ─── (3) NF-14: reload → network → servedFromCache=false, timestamp avanza

  test(
    '(3) NF-14: gasoductos reload network → servedFromCache=false, timestamp avanza',
    () async {
      when(() => mockGasoductos.reload(token: any(named: 'token')))
          .thenAnswer(
            (_) async =>
                const MasterDataLoadResult(MasterDataSource.network, 10),
          );

      await controller.descargar(MasterDataKind.gasoductos);

      final row = controller.rows
          .firstWhere((r) => r.kind == MasterDataKind.gasoductos);
      expect(row.status, equals(MasterDataStatus.success));
      expect(row.servedFromCache, isFalse);
      expect(row.lastDownloadAt, isNotNull);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey('sync_master_last_download_gasoductos'),
        isTrue,
      );
    },
  );

  // ─── (4) NF-15: descargar before _initRows does not throw StateError ──────

  test(
    '(4) NF-15: descargar con rows vacío → no-op, sin StateError',
    () async {
      // Create a fresh controller WITHOUT waiting for _initRows.
      Get.reset();
      SharedPreferences.setMockInitialValues({});
      mockConnectivity = MockConnectivityService();
      mockGasoductos = MockGasoductosService();
      mockPks = MockPksService();
      mockHitos = MockHitosService();
      mockOutbox = MockOutboxQueue();
      mockAuth = MockAuthRepository();

      when(() => mockConnectivity.isConnected).thenReturn(true);
      when(() => mockOutbox.countPending(entityType: any(named: 'entityType')))
          .thenAnswer((_) async => 0);
      when(() => mockGasoductos.totalFiles).thenReturn(RxInt(0));
      when(() => mockGasoductos.processedFiles).thenReturn(RxInt(0));
      when(() => mockPks.totalFiles).thenReturn(RxInt(0));
      when(() => mockPks.processedFiles).thenReturn(RxInt(0));
      when(() => mockHitos.totalFiles).thenReturn(RxInt(0));
      when(() => mockHitos.processedFiles).thenReturn(RxInt(0));

      Get.put<OutboxQueue>(mockOutbox);

      final freshController = SincronizacionController(
        authRepository: mockAuth,
        gasoductosService: mockGasoductos,
        pksService: mockPks,
        hitosService: mockHitos,
        connectivity: mockConnectivity,
      );
      Get.put(freshController);

      // rows is empty at this point (_initRows not awaited yet).
      expect(freshController.rows, isEmpty);

      // Must not throw StateError.
      await expectLater(
        freshController.descargar(MasterDataKind.gasoductos),
        completes,
      );

      await expectLater(
        freshController.descargarTodo(),
        completes,
      );

      // reload should never have been called because rows was empty.
      verifyNever(() => mockGasoductos.reload(token: any(named: 'token')));
    },
  );

  // ─── (5) NF-13: cancelar() passes cancelled token to reload ─────────────

  test(
    '(5) NF-13: cancelar() durante descargarTodo pasa token cancelado a reload',
    () async {
      // Capture the token passed to reload so we can assert it.
      CancelToken? capturedToken;

      when(() => mockGasoductos.reload(token: any(named: 'token')))
          .thenAnswer((invocation) async {
        capturedToken =
            invocation.namedArguments[const Symbol('token')] as CancelToken?;
        // Simulate cancel happening mid-download.
        controller.cancelar();
        return const MasterDataLoadResult(MasterDataSource.network, 3);
      });

      // pks.reload should not be reached if gasoductos cancels first; stub it
      // anyway to avoid "no stubbing" failures in case it is called.
      when(() => mockPks.reload(token: any(named: 'token'))).thenAnswer(
        (_) async => const MasterDataLoadResult(MasterDataSource.network, 2),
      );

      await controller.descargarTodo();

      // The token passed to gasoductos reload must have been cancelled.
      expect(capturedToken, isNotNull);
      expect(capturedToken!.isCancelled, isTrue);
    },
  );
}
