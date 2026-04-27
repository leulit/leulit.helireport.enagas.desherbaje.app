import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  DateTime? _bufferStartedAt;
  int _operadorId = 0;

  OfflineRepository<PositionBatchEntity> get _offline =>
      Get.find<OfflineRepository<PositionBatchEntity>>();

  // ─────────────────────────────── Public API ──────────────────────────

  /// Starts (or resumes from `stopped`) the GPS stream and the periodic
  /// flush timer. Idempotent: a second call while already running is a
  /// no-op.
  Future<void> start() async {
    if (state.value == GpsTrackingState.running) return;
    lastError.value = null;

    final granted = await _ensurePermissions();
    if (!granted) {
      lastError.value = 'Permisos de ubicación denegados.';
      return;
    }

    _operadorId = await _readOperadorId();

    if (Platform.isAndroid) {
      await _startAndroidForegroundService();
    }

    final settings = _platformLocationSettings();
    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: _onPositionError);

    _flushTimer = Timer.periodic(_bufferFlushInterval, (_) {
      unawaited(_flushIfNotEmpty(forceClose: false));
    });

    _bufferStartedAt = DateTime.now();
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
    _buffer.add(PositionPoint(
      capturedAt: p.timestamp,
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

  Future<void> _flushIfNotEmpty({required bool forceClose}) async {
    if (_buffer.isEmpty) return;
    final points = List<PositionPoint>.unmodifiable(_buffer);
    final startedAt = _bufferStartedAt ?? points.first.capturedAt;
    final endedAt = points.last.capturedAt;
    _buffer.clear();
    _bufferStartedAt = forceClose ? null : DateTime.now();

    final batch = PositionBatchEntity(
      operadorId: _operadorId,
      points: points,
      startedAt: startedAt,
      endedAt: endedAt,
    );
    try {
      await _offline.create(batch);
      lastFlushAt.value = DateTime.now();
    } catch (e) {
      lastError.value = 'Error guardando lote GPS: $e';
      if (kDebugMode) {
        debugPrint('GpsBackgroundService flush error: $e');
      }
    }
  }

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

  Future<int> _readOperadorId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsUserIdKey) ?? 0;
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
