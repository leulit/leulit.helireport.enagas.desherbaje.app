import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:leulit_flutter_actionmanager/leulit_flutter_actionmanager.dart';
import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_log.dart';
import '../../core/sync/sync.dart';
import '../../data/sync/traza_local_store.dart';
import '../../domain/entities/traza_entity.dart';
import '../app_typed_actions.dart';

/// State of the GPS tracker exposed to the UI.
enum GpsTrackingState { stopped, running }

/// Manual GPS track ("traza") recorder. Buffers points in memory and
/// append-only flushes them straight into `trazas_puntos` every 500 points
/// or 30 seconds — the outbox is untouched until [finish], which enqueues
/// exactly one push job for the whole traza.
///
/// Lifecycle is driven by the operator explicitly starting/stopping a
/// recording (there is no pause: a traza is either being recorded or it
/// is finished).
///
/// Platform behaviour:
/// - **Android:** runs a foreground service of type `location` so the
///   stream survives the activity going to background. Notification is
///   shown while tracking; `stopWithTask="false"` so it survives the app
///   being swiped from recents.
/// - **iOS:** sets `AppleSettings(allowBackgroundLocationUpdates: true)`;
///   the OS keeps delivering updates to the main isolate. The "blue pill"
///   appears in the status bar while tracking.
class GpsBackgroundService extends GetxService {
  static const int _bufferFlushSize = 500;
  static const Duration _bufferFlushInterval = Duration(seconds: 30);
  static const String _prefsUserIdKey = 'user_id';

  final ValueNotifier<GpsTrackingState> state =
      ValueNotifier(GpsTrackingState.stopped);
  final ValueNotifier<DateTime?> lastFlushAt = ValueNotifier(null);
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  StreamSubscription<Position>? _positionSub;
  Timer? _flushTimer;
  final List<TrazaPunto> _buffer = [];
  // Identity of the traza currently being recorded; null when stopped.
  TrazaEntity? _current;
  // NF-9: nullable — null means "no session yet"; abort start() if null or <= 0.
  int? _operadorId;
  // NF-7: mutex — Dart is single-threaded per isolate; no await between check and set.
  bool _flushing = false;

  late final String _actionHandlerId;

  TrazaLocalStore get _store => DI.get<TrazaLocalStore>();
  OutboxQueue get _outbox => DI.get<OutboxQueue>();

  GpsBackgroundService() {
    // Registered in the constructor (not onInit): get_it does not invoke the
    // GetxService lifecycle, so onInit would silently never run for a
    // service resolved via DI.get instead of GetX's container.
    _actionHandlerId = ActionManager.on<void>(
      AppTypedActions.isTrazaRecordingQuery,
      (event) => isRecording,
    );
  }

  // ─────────────────────────────── Public API ──────────────────────────

  bool get isRecording => state.value == GpsTrackingState.running;

  /// Starts a new traza recording: checks permissions, persists a new open
  /// [TrazaEntity] (name defaulted from now), and starts the GPS stream +
  /// flush timer + Android foreground service.
  ///
  /// Returns `false` (state stays [GpsTrackingState.stopped]) if there is no
  /// valid operador in session or location permissions are missing/denied.
  /// Callers should check [lastError] when this returns `false`.
  Future<bool> start() async {
    if (state.value == GpsTrackingState.running) return true;
    lastError.value = null;

    // NF-9: read operadorId BEFORE starting the foreground service.
    _operadorId = await _readOperadorId();
    if (_operadorId == null || _operadorId! <= 0) {
      lastError.value =
          'No hay operador en sesión; no se inicia el registro de traza.';
      AppLog.w('GpsBackgroundService: start aborted — no valid operadorId');
      return false;
    }

    final granted = await _ensurePermissions();
    if (!granted) {
      lastError.value = 'Permisos de ubicación denegados.';
      return false;
    }

    await _ensureNotificationPermission();

    final traza = TrazaEntity(
      operadorId: _operadorId!,
      startedAt: DateTime.now().toUtc(),
    );
    await _store.upsert(traza);
    _current = traza;

    if (Platform.isAndroid) {
      await _startAndroidForegroundService();
    }

    final settings = _platformLocationSettings();
    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: _onPositionError);

    _flushTimer = Timer.periodic(_bufferFlushInterval, (_) {
      unawaited(_flushIfNotEmpty());
    });

    state.value = GpsTrackingState.running;
    return true;
  }

  /// Closes the current recording: cancels the stream, tears down the
  /// foreground service (Android), flushes whatever points remain in the
  /// buffer (even <500), finalizes the traza with [name] and the current
  /// timestamp, and enqueues exactly one outbox job for it.
  Future<void> finish({required String name}) async {
    if (state.value == GpsTrackingState.stopped || _current == null) return;
    final trazaClientId = _current!.clientId;

    _flushTimer?.cancel();
    _flushTimer = null;
    await _positionSub?.cancel();
    _positionSub = null;

    await _flushIfNotEmpty();

    final endedAt = DateTime.now().toUtc();
    await _store.finalize(
      trazaClientId: trazaClientId,
      name: name,
      endedAt: endedAt,
    );

    if (Platform.isAndroid) {
      await _stopAndroidForegroundService();
    }

    // Enqueue directly on the OutboxQueue — NOT OfflineRepository.create,
    // which would re-`upsert` (wholesale-replace) the points already
    // persisted via appendPoints. LoadEntityTask reloads the full entity
    // (header + points) from the store at drain time.
    await _outbox.enqueue(
      entityType: _store.entityType,
      clientId: trazaClientId,
      operation: SyncOperation.create,
    );

    _current = null;
    state.value = GpsTrackingState.stopped;
  }

  /// The open traza (`endedAt == null`) for [operadorId], if any. Used by the
  /// recovery flow to detect a traza left open by a crash.
  Future<TrazaEntity?> openTrazaFor(int operadorId) =>
      _store.findOpen(operadorId);

  /// Closes a traza left open by a crash: finalizes it with [name] and the
  /// current timestamp and enqueues its outbox job, without touching this
  /// service's in-memory recording state (there is none — the traza was
  /// opened by a previous app instance).
  Future<void> finalizeOpen({
    required String trazaClientId,
    required String name,
  }) async {
    await _store.finalize(
      trazaClientId: trazaClientId,
      name: name,
      endedAt: DateTime.now().toUtc(),
    );
    await _outbox.enqueue(
      entityType: _store.entityType,
      clientId: trazaClientId,
      operation: SyncOperation.create,
    );
  }

  // ─────────────────────────────── Internals ───────────────────────────

  void _onPosition(Position p) {
    if (state.value != GpsTrackingState.running) return;
    // Invariant: _buffer grows by appending at the tail (_buffer.add).
    // removeRange(0, n) relies on this — never insert in the middle.
    _buffer.add(TrazaPunto(
      capturedAt: p.timestamp.toUtc(),
      lat: p.latitude,
      lng: p.longitude,
      accuracyMeters: p.accuracy,
      altitudeMeters: p.altitude,
      speedMps: p.speed,
    ));
    if (_buffer.length >= _bufferFlushSize) {
      unawaited(_flushIfNotEmpty());
    }
  }

  void _onPositionError(Object e) {
    lastError.value = 'Error de GPS: $e';
    if (kDebugMode) {
      debugPrint('GpsBackgroundService stream error: $e');
    }
  }

  // NF-7: write-then-clear with mutex.
  Future<void> _flushIfNotEmpty() async {
    // Mutex: no await between check and set — Dart single-isolate guarantee.
    if (_flushing) return;
    if (_buffer.isEmpty) return;
    final current = _current;
    if (current == null) return;
    _flushing = true;
    try {
      // Snapshot the current buffer length. New points arriving during the
      // await are appended at the tail and are NOT included in this snapshot.
      final points = List<TrazaPunto>.unmodifiable(_buffer);
      await _store.appendPoints(current.clientId, points); // 1) write FIRST
      // 2) Only remove the confirmed points. removeRange(0, n) preserves
      //    points that arrived during the await (appended after index n).
      _buffer.removeRange(0, points.length);
      lastFlushAt.value = DateTime.now();
      lastError.value = null;
    } catch (e, s) {
      // Buffer stays intact = re-appended on next flush.
      lastError.value = 'Error guardando puntos de traza: $e';
      AppLog.e('GpsBackgroundService flush error', error: e, stackTrace: s);
    } finally {
      _flushing = false;
    }
  }

  /// Exposes [_flushIfNotEmpty] for testing (flush-then-clear contract).
  @visibleForTesting
  Future<void> flushNow() => _flushIfNotEmpty();

  /// Directly sets the in-memory buffer for test scenarios that need to
  /// pre-populate points without a real GPS stream.
  @visibleForTesting
  void setBufferForTest(List<TrazaPunto> points) {
    _buffer
      ..clear()
      ..addAll(points);
  }

  /// Sets [_operadorId] and the in-flight [_current] traza for tests that
  /// bypass [start()].
  @visibleForTesting
  void setCurrentForTest(TrazaEntity traza) {
    _operadorId = traza.operadorId;
    _current = traza;
    state.value = GpsTrackingState.running;
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

  /// Android 13+ requires runtime consent to show the foreground-service
  /// notification. Denial does not block recording — the service still runs,
  /// just without a visible notification.
  Future<void> _ensureNotificationPermission() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'GpsBackgroundService: notification permission request failed: $e',
        );
      }
    }
  }

  LocationSettings _platformLocationSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Registrando traza',
          notificationText: 'Helireport mantiene la ubicación activa.',
          enableWakeLock: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        activityType: ActivityType.otherNavigation,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
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
            'Mantiene la app activa para registrar la traza durante la jornada.',
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
        notificationTitle: 'Registrando traza',
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
    ActionManager.off(AppTypedActions.isTrazaRecordingQuery, _actionHandlerId);
    unawaited(_positionSub?.cancel());
    _flushTimer?.cancel();
    super.onClose();
  }
}
