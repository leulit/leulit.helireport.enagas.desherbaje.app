// Tests for the sync DOWNLOAD screen after removing the pre-emptive abort gate
// for segmentos:
//  - pending local changes NO LONGER abort the pull; the segment pull runs and
//    the row ends `success`, carrying a non-blocking warning.
//  - with no pending changes there is no warning.
//  - error/degraded pulls still early-return with an error row and NO warning.
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

class MockConnectivityService extends Mock implements ConnectivityService {}

class MockGasoductosService extends Mock implements GasoductosService {}

class MockPksService extends Mock implements PksService {}

class MockHitosService extends Mock implements HitosService {}

class MockOutboxQueue extends Mock implements OutboxQueue {}

class MockAuthRepository extends Mock implements AuthRepository {}

const _warning =
    'Hay 3 cambios pendientes de subir. Súbelos antes de descargar la lista actualizada.';

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

void main() {
  late MockConnectivityService mockConnectivity;
  late MockGasoductosService mockGasoductos;
  late MockPksService mockPks;
  late MockHitosService mockHitos;
  late MockOutboxQueue mockOutbox;
  late MockAuthRepository mockAuth;
  late SincronizacionController controller;
  late bool pullInvoked;

  MasterDataRow segRow() =>
      controller.rows.firstWhere((r) => r.kind == MasterDataKind.segmentos);

  void stubPending({required int segmentos}) {
    when(() => mockOutbox.countPending(entityType: 'segmento'))
        .thenAnswer((_) async => segmentos);
    when(() => mockOutbox.countPending(entityType: 'imagen'))
        .thenAnswer((_) async => 0);
    when(() => mockOutbox.countPending(entityType: 'mensaje'))
        .thenAnswer((_) async => 0);
    when(() => mockOutbox.countPending(entityType: 'video'))
        .thenAnswer((_) async => 0);
  }

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
    pullInvoked = false;

    when(() => mockConnectivity.isConnected).thenReturn(true);
    when(() => mockHitos.totalFiles).thenReturn(RxInt(0));
    when(() => mockHitos.processedFiles).thenReturn(RxInt(0));

    DI.registerSingleton<OutboxQueue>(mockOutbox);
    OfflineModule.resetPullRunners();
    OfflineModule.registerPullRunnerForTest(
      'segmento',
      ({CancelToken? token}) async {
        pullInvoked = true;
        return _summary(outcome: PullOutcome.ok, upserted: 1);
      },
    );

    controller = SincronizacionController(
      authRepository: mockAuth,
      gasoductosService: mockGasoductos,
      pksService: mockPks,
      hitosService: mockHitos,
      connectivity: mockConnectivity,
    );
    Get.put(controller);
    await Future.delayed(Duration.zero); // let _initRows resolve
  });

  tearDown(() async {
    OfflineModule.resetPullRunners();
    Get.reset();
    await DI.reset();
  });

  test('pending>0 → pull runs (no abort), row success + SAME warning attached',
      () async {
    stubPending(segmentos: 3);

    await controller.descargar(MasterDataKind.segmentos);

    expect(pullInvoked, isTrue);
    final row = segRow();
    expect(row.status, MasterDataStatus.success);
    expect(row.warningMessage, _warning);
  });

  test('pending==0 → pull runs, row success, no warning', () async {
    stubPending(segmentos: 0);

    await controller.descargar(MasterDataKind.segmentos);

    expect(pullInvoked, isTrue);
    final row = segRow();
    expect(row.status, MasterDataStatus.success);
    expect(row.warningMessage, isNull);
  });

  test('degraded (partial) pull → error row, NO success warning even with pending',
      () async {
    stubPending(segmentos: 3);
    OfflineModule.resetPullRunners();
    OfflineModule.registerPullRunnerForTest(
      'segmento',
      ({CancelToken? token}) async {
        pullInvoked = true;
        return _summary(outcome: PullOutcome.partial);
      },
    );

    await controller.descargar(MasterDataKind.segmentos);

    expect(pullInvoked, isTrue);
    final row = segRow();
    expect(row.status, MasterDataStatus.error);
    expect(row.warningMessage, isNull);
  });
}
