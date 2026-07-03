// Tests for SincronizacionController — STEP 8 of WS4.
//
// Focus: `isDegraded` branch in _runOne for MasterDataKind.segmentos.
// - When summary.isDegraded → row becomes error with errorMessage,
//   _persistLastDownload is NOT called.
// - Partial outcome shows a user-friendly fallback message when
//   summary.errorMessage is null.
//
// Strategy: inject fake GasoductosService, PksService, ConnectivityService,
// and seed OfflineModule with a test pull runner so we can return arbitrary
// PullSummary values. OutboxQueue is mocked to return 0 pending (no guard).
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:helireport_desherbaje/core/services/connectivity_service.dart';
import 'package:helireport_desherbaje/core/services/gasoductos_service.dart';
import 'package:helireport_desherbaje/core/services/hitos_service.dart';
import 'package:helireport_desherbaje/core/services/pks_service.dart';
import 'package:helireport_desherbaje/core/sync/offline_module.dart';
import 'package:helireport_desherbaje/core/sync/outbox/outbox_queue.dart';
import 'package:helireport_desherbaje/core/sync/pull/cancel_token.dart';
import 'package:helireport_desherbaje/core/sync/pull/pull_coordinator.dart';
import 'package:helireport_desherbaje/core/sync/pull/pull_outcome.dart';
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

// ─── Helper ──────────────────────────────────────────────────────────────────

PullSummary _summary({
  required PullOutcome outcome,
  String? errorMessage,
  int upserted = 0,
}) =>
    PullSummary(
      total: 0,
      upserted: upserted,
      conflicts: 0,
      cancelled: false,
      authExpired: outcome == PullOutcome.authExpired,
      outcome: outcome,
      errorMessage: errorMessage,
    );

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
    when(() => mockHitos.totalFiles).thenReturn(RxInt(0));
    when(() => mockHitos.processedFiles).thenReturn(RxInt(0));

    // Register OutboxQueue in DI — resolved via AppDI.outboxQueue.
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

  group('_runOne segmentos — isDegraded branch', () {
    test(
      'error outcome → row has error status and errorMessage, lastDownloadAt unchanged',
      () async {
        final errorMsg = 'Exception: network timeout';
        OfflineModule.registerPullRunnerForTest(
          'segmento',
          ({CancelToken? token}) async =>
              _summary(outcome: PullOutcome.error, errorMessage: errorMsg),
        );

        final initialLastDownload = controller
            .rows
            .firstWhere((r) => r.kind == MasterDataKind.segmentos)
            .lastDownloadAt;

        await controller.descargar(MasterDataKind.segmentos);

        final row =
            controller.rows.firstWhere((r) => r.kind == MasterDataKind.segmentos);
        expect(row.status, equals(MasterDataStatus.error));
        expect(row.errorMessage, contains('network timeout'));
        // lastDownloadAt must NOT have advanced.
        expect(row.lastDownloadAt, equals(initialLastDownload));
      },
    );

    test(
      'partial outcome → row has error status with partial message',
      () async {
        OfflineModule.registerPullRunnerForTest(
          'segmento',
          ({CancelToken? token}) async => _summary(
            outcome: PullOutcome.partial,
            errorMessage: null, // null → controller uses fallback message
          ),
        );

        await controller.descargar(MasterDataKind.segmentos);

        final row =
            controller.rows.firstWhere((r) => r.kind == MasterDataKind.segmentos);
        expect(row.status, equals(MasterDataStatus.error));
        expect(row.errorMessage, isNotNull);
        expect(row.errorMessage, isNotEmpty);
      },
    );

    test(
      'isDegraded → SharedPreferences lastDownload key NOT written',
      () async {
        OfflineModule.registerPullRunnerForTest(
          'segmento',
          ({CancelToken? token}) async => _summary(
            outcome: PullOutcome.error,
            errorMessage: 'boom',
          ),
        );

        await controller.descargar(MasterDataKind.segmentos);

        final prefs = await SharedPreferences.getInstance();
        final key = 'sync_master_last_download_segmentos';
        expect(prefs.containsKey(key), isFalse);
      },
    );

    test(
      'ok outcome (control) → row becomes success, lastDownloadAt IS set',
      () async {
        OfflineModule.registerPullRunnerForTest(
          'segmento',
          ({CancelToken? token}) async => _summary(outcome: PullOutcome.ok),
        );

        await controller.descargar(MasterDataKind.segmentos);

        final row =
            controller.rows.firstWhere((r) => r.kind == MasterDataKind.segmentos);
        expect(row.status, equals(MasterDataStatus.success));
        expect(row.lastDownloadAt, isNotNull);
      },
    );
  });

  group('_runOne posicionesFijas — pull-only branch', () {
    test('ok outcome → row becomes success, lastDownloadAt IS set', () async {
      OfflineModule.registerPullRunnerForTest(
        'posicion_fija',
        ({CancelToken? token}) async => _summary(outcome: PullOutcome.ok),
      );

      await controller.descargar(MasterDataKind.posicionesFijas);

      final row = controller.rows
          .firstWhere((r) => r.kind == MasterDataKind.posicionesFijas);
      expect(row.status, equals(MasterDataStatus.success));
      expect(row.lastDownloadAt, isNotNull);
    });

    test(
      'isDegraded (error) → row has error status with fallback message',
      () async {
        OfflineModule.registerPullRunnerForTest(
          'posicion_fija',
          ({CancelToken? token}) async => _summary(
            outcome: PullOutcome.error,
            errorMessage: null,
          ),
        );

        await controller.descargar(MasterDataKind.posicionesFijas);

        final row = controller.rows
            .firstWhere((r) => r.kind == MasterDataKind.posicionesFijas);
        expect(row.status, equals(MasterDataStatus.error));
        expect(row.errorMessage, contains('posiciones fijas'));

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.containsKey('sync_master_last_download_posicionesFijas'),
          isFalse,
        );
      },
    );

    test('cancelled → row goes back to idle', () async {
      OfflineModule.registerPullRunnerForTest(
        'posicion_fija',
        ({CancelToken? token}) async => const PullSummary(
          total: 0,
          upserted: 0,
          conflicts: 0,
          cancelled: true,
          outcome: PullOutcome.cancelled,
        ),
      );

      await controller.descargar(MasterDataKind.posicionesFijas);

      final row = controller.rows
          .firstWhere((r) => r.kind == MasterDataKind.posicionesFijas);
      expect(row.status, equals(MasterDataStatus.idle));
    });

    test('authExpired → row has error with session-expired message', () async {
      OfflineModule.registerPullRunnerForTest(
        'posicion_fija',
        ({CancelToken? token}) async =>
            _summary(outcome: PullOutcome.authExpired),
      );

      await controller.descargar(MasterDataKind.posicionesFijas);

      final row = controller.rows
          .firstWhere((r) => r.kind == MasterDataKind.posicionesFijas);
      expect(row.status, equals(MasterDataStatus.error));
      expect(row.errorMessage, contains('sesión'));
    });
  });
}
