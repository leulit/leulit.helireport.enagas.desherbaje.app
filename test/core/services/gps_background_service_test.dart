import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:helireport_desherbaje/core/services/gps_background_service.dart';
import 'package:helireport_desherbaje/core/sync/sync.dart';
import 'package:helireport_desherbaje/data/sync/traza_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/traza_entity.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class _MockStore extends Mock implements TrazaLocalStore {}

class _MockOutbox extends Mock implements OutboxQueue {}

/// Sólo se pasa a `any()`; nunca se interactúa con él.
class _FakeTraza extends Fake implements TrazaEntity {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Returns a service with mocks registered in DI. Does NOT call start() —
/// bypasses Geolocator/foreground service plugins.
GpsBackgroundService _buildService(_MockStore store, _MockOutbox outbox) {
  DI.registerSingleton<TrazaLocalStore>(store);
  DI.registerSingleton<OutboxQueue>(outbox);
  when(() => store.entityType).thenReturn('traza');
  return GpsBackgroundService();
}

TrazaPunto _point(DateTime capturedAt) =>
    TrazaPunto(capturedAt: capturedAt, lat: 40.0, lng: -3.0);

void main() {
  late _MockStore store;
  late _MockOutbox outbox;
  late GpsBackgroundService svc;

  setUpAll(() {
    registerFallbackValue(SyncOperation.create);
    registerFallbackValue(_FakeTraza());
    registerFallbackValue(<TrazaPunto>[]);
  });

  setUp(() async {
    Get.reset();
    await DI.reset();
    store = _MockStore();
    outbox = _MockOutbox();
    svc = _buildService(store, outbox);
  });

  tearDown(() async {
    Get.reset();
    await DI.reset();
  });

  TrazaEntity currentTraza(int operadorId) => TrazaEntity(
        clientId: 'traza-test',
        operadorId: operadorId,
        startedAt: DateTime.utc(2025, 6, 1, 10, 0),
      );

  // ─── NF-7: write-then-clear ───────────────────────────────────────────────

  group('NF-7 write-then-clear (buffer survives failed flush)', () {
    test(
        'appendPoints() throws → lastError set, buffer remains intact for '
        'retry', () async {
      svc.setCurrentForTest(currentTraza(1));
      final t = DateTime.utc(2025, 6, 1, 10, 0);
      final pts = [_point(t), _point(t.add(const Duration(seconds: 1)))];
      svc.setBufferForTest(pts);

      when(() => store.appendPoints(any(), any()))
          .thenThrow(Exception('DB error'));

      await svc.flushNow();

      expect(svc.lastError.value, isNotNull);
      expect(svc.lastError.value, contains('Error guardando puntos de traza'));

      // Buffer is intact — all original points still available for retry.
      when(() => store.appendPoints(any(), any())).thenAnswer((_) async {});
      await svc.flushNow();

      expect(svc.lastError.value, isNull);
      final captured =
          verify(() => store.appendPoints(any(), captureAny())).captured;
      // First call (failed) + second call (succeeded)
      expect(captured.length, equals(2));
      final secondPoints = captured.last as List<TrazaPunto>;
      expect(secondPoints.length, equals(2));
    });

    test('point added during awaited appendPoints() is preserved', () async {
      svc.setCurrentForTest(currentTraza(1));
      final t = DateTime.utc(2025, 6, 1, 10, 0);
      svc.setBufferForTest([_point(t)]);

      final completer = Completer<void>();
      when(() => store.appendPoints(any(), any()))
          .thenAnswer((_) => completer.future);

      final flushFuture = svc.flushNow();

      // Simulate a new position arriving while appendPoints() is in flight:
      // the real buffer would contain [original, new] at the time
      // removeRange runs (after await), since _onPosition appends at the tail.
      svc.setBufferForTest(
          [_point(t), _point(t.add(const Duration(seconds: 5)))]);

      completer.complete();
      await flushFuture;

      // After successful flush, removeRange(0, 1) removed the first point.
      // The "new" point (index 1) survives and will be sent in the next flush.
      when(() => store.appendPoints(any(), any())).thenAnswer((_) async {});
      await svc.flushNow();

      final captured =
          verify(() => store.appendPoints(any(), captureAny())).captured;
      final secondPoints = captured.last as List<TrazaPunto>;
      expect(secondPoints.length, greaterThan(0));
    });
  });

  // ─── NF-7: mutex (no double-send) ────────────────────────────────────────

  group('NF-7 mutex — two concurrent flushNow() calls', () {
    test(
        'second flushNow() returns immediately (_flushing guard), '
        'no double-send', () async {
      svc.setCurrentForTest(currentTraza(1));
      final t = DateTime.utc(2025, 6, 1, 11, 0);
      svc.setBufferForTest([_point(t)]);

      final completer = Completer<void>();
      when(() => store.appendPoints(any(), any()))
          .thenAnswer((_) => completer.future);

      final first = svc.flushNow();
      final second = svc.flushNow();

      await second; // should not block

      completer.complete();
      await first;

      verify(() => store.appendPoints(any(), any())).called(1);
    });
  });

  // ─── NF-9: abort without valid operadorId ────────────────────────────────

  group('NF-9 start() aborts without valid operador', () {
    test(
        'no user_id key in prefs → state stays stopped, lastError set, '
        'verifyNever(upsert)', () async {
      SharedPreferences.setMockInitialValues({});

      final started = await svc.start();

      expect(started, isFalse);
      expect(svc.state.value, equals(GpsTrackingState.stopped));
      expect(svc.lastError.value, isNotNull);
      expect(svc.lastError.value, contains('operador'));
      verifyNever(() => store.upsert(any()));
    });

    test('user_id = 0 → abort (treated as no session)', () async {
      SharedPreferences.setMockInitialValues({'user_id': 0});

      final started = await svc.start();

      expect(started, isFalse);
      expect(svc.state.value, equals(GpsTrackingState.stopped));
      expect(svc.lastError.value, isNotNull);
      verifyNever(() => store.upsert(any()));
    });
  });

  // ─── finish() ─────────────────────────────────────────────────────────────

  group('finish()', () {
    test('flushes remaining buffer, finalizes and enqueues exactly one job',
        () async {
      final traza = currentTraza(1);
      svc.setCurrentForTest(traza);
      final t = DateTime.utc(2025, 6, 1, 10, 5);
      svc.setBufferForTest([_point(t)]);

      when(() => store.appendPoints(any(), any())).thenAnswer((_) async {});
      when(() => store.finalize(
            trazaClientId: any(named: 'trazaClientId'),
            name: any(named: 'name'),
            endedAt: any(named: 'endedAt'),
          )).thenAnswer((_) async {});
      when(() => outbox.enqueue(
            entityType: any(named: 'entityType'),
            clientId: any(named: 'clientId'),
            operation: any(named: 'operation'),
          )).thenAnswer((_) async => 1);

      await svc.finish(name: 'Mi traza');

      verify(() => store.appendPoints(traza.clientId, any())).called(1);
      verify(() => store.finalize(
            trazaClientId: traza.clientId,
            name: 'Mi traza',
            endedAt: any(named: 'endedAt'),
          )).called(1);
      verify(() => outbox.enqueue(
            entityType: 'traza',
            clientId: traza.clientId,
            operation: SyncOperation.create,
          )).called(1);
      expect(svc.state.value, equals(GpsTrackingState.stopped));
    });

    test('is a no-op when nothing is currently recording', () async {
      await svc.finish(name: 'ignored');
      verifyNever(() => store.finalize(
            trazaClientId: any(named: 'trazaClientId'),
            name: any(named: 'name'),
            endedAt: any(named: 'endedAt'),
          ));
      verifyNever(() => outbox.enqueue(
            entityType: any(named: 'entityType'),
            clientId: any(named: 'clientId'),
            operation: any(named: 'operation'),
          ));
    });
  });
}
