import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../engine/sync_engine.dart';
import '../outbox/outbox_queue.dart';
import 'background_sync_task_handler.dart';

class BackgroundSyncConfig {
  final String notificationTitle;
  final String notificationText;
  final String channelId;
  final String channelName;
  final String channelDescription;

  const BackgroundSyncConfig({
    this.notificationTitle = 'Sincronización en curso',
    this.notificationText = 'Enviando datos pendientes',
    this.channelId = 'leulit_sync_channel',
    this.channelName = 'Sincronización',
    this.channelDescription =
        'Mantiene la aplicación activa para subir datos pendientes',
  });
}

class BackgroundSyncCoordinator {
  final OutboxQueue _outbox;
  final SyncEngine _engine;
  final BackgroundSyncConfig _config;

  AppLifecycleListener? _lifecycle;
  StreamSubscription<void>? _outboxSub;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _serviceRunning = false;
  bool _transitioning = false;
  bool _initialized = false;

  BackgroundSyncCoordinator({
    required OutboxQueue outbox,
    required SyncEngine engine,
    BackgroundSyncConfig config = const BackgroundSyncConfig(),
  })  : _outbox = outbox,
        _engine = engine,
        _config = config;

  Future<void> start() async {
    if (_initialized) return;
    _initialized = true;

    if (!Platform.isAndroid && !Platform.isIOS) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _config.channelId,
        channelName: _config.channelName,
        channelDescription: _config.channelDescription,
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

    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    _outboxSub = _outbox.changes.listen((_) => _reconcile());
  }

  Future<void> stop() async {
    _lifecycle?.dispose();
    _lifecycle = null;
    await _outboxSub?.cancel();
    _outboxSub = null;
    if (_serviceRunning) {
      await _stopService();
    }
    _initialized = false;
  }

  void _onLifecycle(AppLifecycleState state) {
    _lifecycleState = state;
    _reconcile();
  }

  Future<void> _reconcile() async {
    if (_transitioning) return;
    _transitioning = true;
    try {
      final pending = await _outbox.countPending();
      final shouldRun =
          pending > 0 && _lifecycleState != AppLifecycleState.resumed;

      if (shouldRun && !_serviceRunning) {
        await _startService();
      } else if (!shouldRun && _serviceRunning) {
        await _stopService();
      }
    } finally {
      _transitioning = false;
    }
  }

  Future<void> _startService() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await FlutterForegroundTask.startService(
        serviceTypes: Platform.isAndroid
            ? const [ForegroundServiceTypes.dataSync]
            : null,
        notificationTitle: _config.notificationTitle,
        notificationText: _config.notificationText,
        callback: backgroundSyncTaskEntrypoint,
      );
      _serviceRunning = true;
      unawaited(_engine.drain());
    } catch (e) {
      debugPrint('[BackgroundSyncCoordinator] startService failed: $e');
    }
  }

  Future<void> _stopService() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('[BackgroundSyncCoordinator] stopService failed: $e');
    } finally {
      _serviceRunning = false;
    }
  }
}
