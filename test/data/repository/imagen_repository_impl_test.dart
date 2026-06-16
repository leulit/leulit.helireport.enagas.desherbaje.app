import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:helireport_desherbaje/core/services/connectivity_service.dart';
import 'package:helireport_desherbaje/core/sync/sync.dart';
import 'package:helireport_desherbaje/data/repository/imagen_repository_impl.dart';
import 'package:helireport_desherbaje/domain/entities/imagen_segmento_entity.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockConnectivity extends Mock implements ConnectivityService {}

class _MockEngine extends Mock implements SyncEngine {}

class _MockOfflineRepository extends Mock
    implements OfflineRepository<ImagenSegmentoEntity> {}

// ---------------------------------------------------------------------------
// H: offline guard — uploadPending returns empty DrainSummary, engine skipped
// ---------------------------------------------------------------------------

void main() {
  late _MockConnectivity connectivity;
  late _MockEngine engine;
  late _MockOfflineRepository offline;
  late ImagenRepositoryImpl repo;

  setUp(() {
    connectivity = _MockConnectivity();
    engine = _MockEngine();
    offline = _MockOfflineRepository();

    repo = ImagenRepositoryImpl(
      offline: offline,
      engine: engine,
      connectivity: connectivity,
    );
  });

  test('H – offline: uploadPending returns empty DrainSummary, '
      'engine.drain never called', () async {
    when(() => connectivity.isConnected).thenReturn(false);

    final result = await repo.uploadPending(42);

    expect(result.succeeded, equals(0));
    expect(result.retryable, equals(0));
    expect(result.rejected, equals(0));
    expect(result.conflicts, equals(0));
    expect(result.authExpired, isFalse);

    verifyNever(() => engine.drain(entityType: any(named: 'entityType')));
  });

  test('H-online – online: uploadPending delegates to engine.drain', () async {
    when(() => connectivity.isConnected).thenReturn(true);
    when(() => engine.drain(entityType: 'imagen')).thenAnswer(
      (_) async => const DrainSummary(succeeded: 3),
    );

    final result = await repo.uploadPending(42);

    expect(result.succeeded, equals(3));
    verify(() => engine.drain(entityType: 'imagen')).called(1);
  });
}
