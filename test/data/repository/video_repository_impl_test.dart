import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:helireport_desherbaje/core/services/connectivity_service.dart';
import 'package:helireport_desherbaje/core/sync/sync.dart';
import 'package:helireport_desherbaje/data/repository/video_repository_impl.dart';
import 'package:helireport_desherbaje/domain/entities/video_segmento_entity.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockConnectivity extends Mock implements ConnectivityService {}

class _MockEngine extends Mock implements SyncEngine {}

class _MockOfflineRepository extends Mock
    implements OfflineRepository<VideoSegmentoEntity> {}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockConnectivity connectivity;
  late _MockEngine engine;
  late _MockOfflineRepository offline;
  late VideoRepositoryImpl repo;

  setUp(() {
    connectivity = _MockConnectivity();
    engine = _MockEngine();
    offline = _MockOfflineRepository();

    repo = VideoRepositoryImpl(
      offline: offline,
      engine: engine,
      connectivity: connectivity,
    );
  });

  test('offline: uploadAllPending returns empty DrainSummary, '
      'engine.drain never called', () async {
    when(() => connectivity.isConnected).thenReturn(false);

    final result = await repo.uploadAllPending();

    expect(result.succeeded, equals(0));
    expect(result.retryable, equals(0));
    expect(result.rejected, equals(0));
    expect(result.conflicts, equals(0));
    expect(result.authExpired, isFalse);

    verifyNever(() => engine.drain(entityType: any(named: 'entityType')));
  });

  test('online: uploadAllPending delegates to engine.drain with entityType video', () async {
    when(() => connectivity.isConnected).thenReturn(true);
    when(() => engine.drain(entityType: 'video')).thenAnswer(
      (_) async => const DrainSummary(succeeded: 2),
    );

    final result = await repo.uploadAllPending();

    expect(result.succeeded, equals(2));
    verify(() => engine.drain(entityType: 'video')).called(1);
  });
}
