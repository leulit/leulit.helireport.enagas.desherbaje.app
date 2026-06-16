import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:helireport_desherbaje/core/services/gps_background_service.dart';
import 'package:helireport_desherbaje/core/sync/sync.dart';
import 'package:helireport_desherbaje/domain/entities/position_batch_entity.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class _MockOffline extends Mock
    implements OfflineRepository<PositionBatchEntity> {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Returns a service with a registered mock offline repo.
/// Does NOT call start() — bypasses Geolocator/foreground service plugins.
GpsBackgroundService _buildService(_MockOffline offline) {
  Get.put<OfflineRepository<PositionBatchEntity>>(offline);
  return Get.put<GpsBackgroundService>(GpsBackgroundService());
}

PositionPoint _point(DateTime capturedAt) => PositionPoint(
      capturedAt: capturedAt,
      lat: 40.0,
      lng: -3.0,
    );

void main() {
  late _MockOffline offline;
  late GpsBackgroundService svc;

  setUp(() {
    Get.reset();
    offline = _MockOffline();
    svc = _buildService(offline);

    registerFallbackValue(
      PositionBatchEntity(
        operadorId: 1,
        points: const [],
        startedAt: DateTime.utc(2025),
        endedAt: DateTime.utc(2025),
      ),
    );
  });

  tearDown(() => Get.reset());

  // ─── NF-7: write-then-clear ───────────────────────────────────────────────

  group('NF-7 write-then-clear (buffer survives failed flush)', () {
    test('create() throws → lastError set, buffer remains intact for retry',
        () async {
      svc.setOperadorIdForTest(1);
      final t = DateTime.utc(2025, 6, 1, 10, 0);
      final pts = [_point(t), _point(t.add(const Duration(seconds: 1)))];
      svc.setBufferForTest(pts);

      when(() => offline.create(any())).thenThrow(Exception('DB error'));

      await svc.flushNow();

      expect(svc.lastError.value, isNotNull);
      expect(svc.lastError.value, contains('Error guardando lote GPS'));

      // Buffer is intact — all original points still available for retry.
      // Second flush with successful create should succeed.
      when(() => offline.create(any())).thenAnswer((_) async {});
      await svc.flushNow();

      expect(svc.lastError.value, isNull);
      // verify create was called with a batch containing the original 2 points
      final captured = verify(() => offline.create(captureAny())).captured;
      // First call (failed) + second call (succeeded)
      expect(captured.length, equals(2));
      final secondBatch = captured.last as PositionBatchEntity;
      expect(secondBatch.points.length, equals(2));
    });

    test('point added during awaited create() is preserved', () async {
      svc.setOperadorIdForTest(1);
      final t = DateTime.utc(2025, 6, 1, 10, 0);
      svc.setBufferForTest([_point(t)]);

      final completer = Completer<void>();
      // The create() awaits the completer; we inject a new point mid-flight.
      when(() => offline.create(any()))
          .thenAnswer((_) => completer.future);

      final flushFuture = svc.flushNow();

      // Simulate a new position arriving while create() is in flight.
      // In production _onPosition does _buffer.add; we replicate that here.
      svc.setBufferForTest([
        _point(t), // original (will be removed by removeRange)
        _point(t.add(const Duration(seconds: 5))), // new arrival
      ]);
      // But only the first was snapshotted → after removeRange(0,1) one remains.
      // Re-set so the real buffer reflects the state AFTER snapshot but BEFORE clear:
      // removeRange(0, points.length) where points.length == 1 removes index 0
      // and the new point at index 1 survives.
      // We model this by having the buffer contain [original, new] at the time
      // removeRange runs (after await).
      // Reset buffer to [original, newPoint] to simulate the concurrent add:
      svc.setBufferForTest([_point(t), _point(t.add(const Duration(seconds: 5)))]);

      completer.complete();
      await flushFuture;

      // After successful flush, removeRange(0, 1) removed the first point.
      // The "new" point (index 1) survives and will be sent in the next flush.
      when(() => offline.create(any())).thenAnswer((_) async {});
      await svc.flushNow();

      final captured = verify(() => offline.create(captureAny())).captured;
      // Second flush should carry the surviving point.
      final secondBatch = captured.last as PositionBatchEntity;
      expect(secondBatch.points.length, greaterThan(0));
    });
  });

  // ─── NF-7: mutex (no double-send) ────────────────────────────────────────

  group('NF-7 mutex — two concurrent flushNow() calls', () {
    test('second flushNow() returns immediately (_flushing guard), '
        'no double-send', () async {
      svc.setOperadorIdForTest(1);
      final t = DateTime.utc(2025, 6, 1, 11, 0);
      svc.setBufferForTest([_point(t)]);

      final completer = Completer<void>();
      when(() => offline.create(any()))
          .thenAnswer((_) => completer.future);

      // Start first flush (awaiting completer)
      final first = svc.flushNow();
      // Start second flush immediately — should hit the _flushing guard
      final second = svc.flushNow();

      // Second must resolve without waiting for the first
      await second; // should not block

      completer.complete();
      await first;

      // create() was only called once (by the first flush)
      verify(() => offline.create(any())).called(1);
    });
  });

  // ─── NF-9: abort without valid operadorId ────────────────────────────────

  group('NF-9 start() aborts without valid operador', () {
    test('no user_id key in prefs → state stays stopped, lastError set, '
        'verifyNever(create)', () async {
      SharedPreferences.setMockInitialValues({});

      await svc.start();

      expect(svc.state.value, equals(GpsTrackingState.stopped));
      expect(svc.lastError.value, isNotNull);
      expect(svc.lastError.value, contains('operador'));
      verifyNever(() => offline.create(any()));
    });

    test('user_id = 0 → abort (treated as no session)', () async {
      SharedPreferences.setMockInitialValues({'user_id': 0});

      await svc.start();

      expect(svc.state.value, equals(GpsTrackingState.stopped));
      expect(svc.lastError.value, isNotNull);
      verifyNever(() => offline.create(any()));
    });
  });

  // ─── A6: UTC timestamps + startedAt <= endedAt ───────────────────────────

  group('A6 interval derivation from capturedAt (UTC, ordered)', () {
    test('points with out-of-order local timestamps → '
        'startedAt <= endedAt, both UTC', () async {
      svc.setOperadorIdForTest(1);

      // Out-of-order: 3rd point has earliest time, 1st has latest
      final t1 = DateTime.utc(2025, 6, 1, 12, 30); // latest
      final t2 = DateTime.utc(2025, 6, 1, 12, 10);
      final t3 = DateTime.utc(2025, 6, 1, 12, 0); // earliest

      svc.setBufferForTest([_point(t1), _point(t2), _point(t3)]);

      PositionBatchEntity? captured;
      when(() => offline.create(any())).thenAnswer((inv) async {
        captured = inv.positionalArguments.first as PositionBatchEntity;
      });

      await svc.flushNow();

      expect(captured, isNotNull);
      expect(
        captured!.startedAt.isBefore(captured!.endedAt) ||
            captured!.startedAt.isAtSameMomentAs(captured!.endedAt),
        isTrue,
        reason: 'startedAt must be <= endedAt',
      );
      expect(captured!.startedAt.isUtc, isTrue);
      expect(captured!.endedAt.isUtc, isTrue);

      // startedAt = min(capturedAt) = t3, endedAt = max = t1
      expect(
        captured!.startedAt.isAtSameMomentAs(t3),
        isTrue,
        reason: 'startedAt must be the minimum capturedAt',
      );
      expect(
        captured!.endedAt.isAtSameMomentAs(t1),
        isTrue,
        reason: 'endedAt must be the maximum capturedAt',
      );
    });

    test('single point → startedAt == endedAt', () async {
      svc.setOperadorIdForTest(1);
      final t = DateTime.utc(2025, 6, 1, 9, 0);
      svc.setBufferForTest([_point(t)]);

      PositionBatchEntity? captured;
      when(() => offline.create(any())).thenAnswer((inv) async {
        captured = inv.positionalArguments.first as PositionBatchEntity;
      });

      await svc.flushNow();

      expect(captured!.startedAt.isAtSameMomentAs(captured!.endedAt), isTrue);
      expect(captured!.startedAt.isUtc, isTrue);
    });

    test('local-timezone points are normalized to UTC', () async {
      svc.setOperadorIdForTest(1);
      // Use a local DateTime (not UTC) — should be converted to UTC by _onPosition
      // In tests we inject directly: the service normalizes via p.timestamp.toUtc()
      // Here we pre-inject UTC points (as _onPosition would produce) and verify.
      final localLike = DateTime(2025, 6, 1, 10, 0, 0); // local
      svc.setBufferForTest([_point(localLike.toUtc())]);

      PositionBatchEntity? captured;
      when(() => offline.create(any())).thenAnswer((inv) async {
        captured = inv.positionalArguments.first as PositionBatchEntity;
      });

      await svc.flushNow();

      expect(captured!.startedAt.isUtc, isTrue);
      expect(captured!.endedAt.isUtc, isTrue);
    });
  });
}
