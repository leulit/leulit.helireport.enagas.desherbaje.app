import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_log.dart';
import '../../core/sync/sync.dart';
import '../../domain/entities/position_batch_entity.dart';

/// State of the GPS tracker exposed to the UI.
enum GpsTrackingState { stopped, running, paused }

/// Background-aware GPS tracker. Buffers points in memory and flushes a
/// batch to SQLite + outbox every 500 points or 30 seconds.
///
/// Lifecycle is driven by the controller of the Mapa screen
/// (`MapaGlobalController.onInit/onClose`); the service must be `stop`-ed
/// when the operator leaves the map (decision P15).
///
/// Platform behaviour:
/// - **Android:** runs a foreground service of type `location` so the
///   stream survives the activity going to background. Notification is
///   shown while tracking.
/// - **iOS:** sets `AppleSettings(allowBackgroundLocationUpdates: true)`;
///   the OS keeps delivering updates to the main isolate. The "blue pill"
///   appears in the status bar while tracking.
class GpsBackgroundService extends GetxService {
  static const int _bufferFlushSize = 500;
  static const Duration _bufferFlushInterval = Duration(seconds: 30);
  static const String _prefsUserIdKey = 'user_id';

  final state = GpsTrackingState.stopped.obs;
  final lastFlushAt = Rxn<DateTime>();
  final lastError = Rxn<String>();

  StreamSubscription<Position>? _positionSub;
  Timer? _flushTimer;
  final List<PositionPoint> _buffer = [];
  // NF-9: nullable — null means "no session yet"; abort start() if null or <= 0.
  int? _operadorId;
  // NF-7: mutex — Dart is single-threaded per isolate; no await between check and set.
  bool _flushing = false;

  OfflineRepository<PositionBatchEntity> get _offline =>
      Get.find<OfflineRepository<PositionBatchEntity>>();

  // ─────────────────────────────── Public API ──────────────────────────

  /// Starts (or resumes from `stopped`) the GPS stream and the periodic
  /// flush timer. Idempotent: a second call while already running is a
  /// no-op.
  ///
  /// NF-9: aborts (state stays stopped) if no valid operador in session.
  /// Callers should check [lastError] after start() returns.
  Future<void> start() async {
    if (state.value == GpsTrackingState.running) return;
    lastError.value = null;

    // NF-9: read operadorId BEFORE starting the foreground service.
    _operadorId = await _readOperadorId();
    if (_operadorId == null || _operadorId! <= 0) {
      lastError.value =
          'No hay operador en sesión; no se inicia el tracking GPS.';
      AppLog.w('GpsBackgroundService: start aborted — no valid operadorId');
      return;
    }

    final granted = await _ensurePermissions();
    if (!granted) {
      lastError.value = 'Permisos de ubicación denegados.';
      return;
    }

    if (Platform.isAndroid) {
      await _startAndroidForegroundService();
    }

    final settings = _platformLocationSettings();
    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: _onPositionError);

    _flushTimer = Timer.periodic(_bufferFlushInterval, (_) {
      unawaited(_flushIfNotEmpty(forceClose: false));
    });

    state.value = GpsTrackingState.running;
  }

  /// Drops incoming points without tearing down the stream / service.
  /// Buffer stays open; resuming continues building the same batch.
  void pause() {
    if (state.value != GpsTrackingState.running) return;
    state.value = GpsTrackingState.paused;
  }

  void resume() {
    if (state.value != GpsTrackingState.paused) return;
    state.value = GpsTrackingState.running;
  }

  /// Closes the tracker: cancels the stream, tears down the foreground
  /// service (Android), flushes whatever points remain in the buffer
  /// (even <500), and enqueues the final batch in the outbox.
  Future<void> stop() async {
    if (state.value == GpsTrackingState.stopped) return;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _positionSub?.cancel();
    _positionSub = null;

    await _flushIfNotEmpty(forceClose: true);

    if (Platform.isAndroid) {
      await _stopAndroidForegroundService();
    }
    state.value = GpsTrackingState.stopped;
  }

  // ─────────────────────────────── Internals ───────────────────────────

  void _onPosition(Position p) {
    if (state.value != GpsTrackingState.running) return;
    // A6: normalize capturedAt to UTC for coherence across store/JSON/derivation.
    // Invariant: _buffer grows by appending at the tail (_buffer.add).
    // removeRange(0, n) relies on this — never insert in the middle.
    _buffer.add(PositionPoint(
      capturedAt: p.timestamp.toUtc(),
      lat: p.latitude,
      lng: p.longitude,
      accuracyMeters: p.accuracy,
      altitudeMeters: p.altitude,
      speedMps: p.speed,
    ));
    if (_buffer.length >= _bufferFlushSize) {
      unawaited(_flushIfNotEmpty(forceClose: false));
    }
  }

  void _onPositionError(Object e) {
    lastError.value = 'Error de GPS: $e';
    if (kDebugMode) {
      debugPrint('GpsBackgroundService stream error: $e');
    }
  }

  // NF-7: write-then-clear with mutex.
  // NF-9: _operadorId is guaranteed non-null and > 0 here (abort guard in start()).
  Future<void> _flushIfNotEmpty({required bool forceClose}) async {
    // [REVIEW G4] Mutex: no await between check and set — Dart single-isolate guarantee.
    if (_flushing) return;
    if (_buffer.isEmpty) return;
    _flushing = true;
    try {
      // Snapshot the current buffer length. New points arriving during the
      // await are appended at the tail and are NOT included in this snapshot.
      final points = List<PositionPoint>.unmodifiable(_buffer);
      final (startedAt, endedAt) = _deriveInterval(points); // A6
      final batch = PositionBatchEntity(
        operadorId: _operadorId!, // guaranteed by NF-9 guard in start()
        points: points,
        startedAt: startedAt,
        endedAt: endedAt,
      );
      await _offline.create(batch); // 1) persist FIRST
      // 2) Only remove the confirmed points. removeRange(0, n) preserves points
      //    that arrived during the await (appended after index n).
      _buffer.removeRange(0, points.length);
      lastFlushAt.value = DateTime.now();
      lastError.value = null;
    } catch (e, s) {
      // Buffer stays intact = re-enqueue on next flush (create tx is atomic).
      lastError.value = 'Error guardando lote GPS: $e';
      AppLog.e('GpsBackgroundService flush error', error: e, stackTrace: s);
    } finally {
      _flushing = false;
    }
  }

  /// A6: derives [startedAt, endedAt] from the min/max capturedAt (UTC).
  /// Guarantees end >= start even if points arrive out-of-order.
  (DateTime, DateTime) _deriveInterval(List<PositionPoint> pts) {
    var start = pts.first.capturedAt.toUtc();
    var end = pts.first.capturedAt.toUtc();
    for (final p in pts) {
      final c = p.capturedAt.toUtc();
      if (c.isBefore(start)) start = c;
      if (c.isAfter(end)) end = c;
    }
    if (end.isBefore(start)) end = start;
    return (start, end);
  }

  /// Exposes [_flushIfNotEmpty] for testing (flush-then-clear contract).
  @visibleForTesting
  Future<void> flushNow() => _flushIfNotEmpty(forceClose: false);

  /// Directly sets the in-memory buffer for test scenarios that need to
  /// pre-populate points without a real GPS stream.
  @visibleForTesting
  void setBufferForTest(List<PositionPoint> points) {
    _buffer
      ..clear()
      ..addAll(points);
  }

  /// Sets [_operadorId] for tests that bypass [start()].
  @visibleForTesting
  void setOperadorIdForTest(int? id) => _operadorId = id;

  Future<bool> _ensurePermissions() async {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      final requested = await Geolocator.requestPermission();
      return requested == LocationPermission.always ||
          requested == LocationPermission.whileInUse;
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  LocationSettings _platformLocationSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Registrando posición',
          notificationText: 'Helireport mantiene la ubicación activa.',
          enableWakeLock: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        activityType: ActivityType.otherNavigation,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );
  }

  // NF-9: returns null if the key is absent (no session); no ?? 0 fallback.
  Future<int?> _readOperadorId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsUserIdKey);
  }

  Future<void> _startAndroidForegroundService() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'leulit_gps_channel',
        channelName: 'Tracking GPS',
        channelDescription:
            'Mantiene la app activa para registrar la posición durante la jornada.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    try {
      await FlutterForegroundTask.startService(
        serviceTypes: const [ForegroundServiceTypes.location],
        notificationTitle: 'Registrando posición',
        notificationText: 'Helireport mantiene la ubicación activa.',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'GpsBackgroundService: foreground service start failed: $e',
        );
      }
    }
  }

  Future<void> _stopAndroidForegroundService() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'GpsBackgroundService: foreground service stop failed: $e',
        );
      }
    }
  }

  @override
  void onClose() {
    unawaited(stop());
    super.onClose();
  }
}
