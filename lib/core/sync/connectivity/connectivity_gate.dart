import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../sync_actions.dart';

class ConnectivityGateConfig {
  final String? pingHost;
  final Duration heartbeatInterval;
  final Duration probeTimeout;
  final Duration cacheWindow;

  const ConnectivityGateConfig({
    this.pingHost,
    this.heartbeatInterval = const Duration(seconds: 15),
    this.probeTimeout = const Duration(seconds: 4),
    this.cacheWindow = const Duration(seconds: 3),
  });
}

class ConnectivityGate {
  final Connectivity _connectivity;
  final ConnectivityGateConfig _config;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _heartbeat;

  bool _isOnline = false;
  bool _started = false;
  DateTime _lastProbeAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _lastProbeResult = false;

  ConnectivityGate({
    Connectivity? connectivity,
    ConnectivityGateConfig config = const ConnectivityGateConfig(),
  })  : _connectivity = connectivity ?? Connectivity(),
        _config = config;

  bool get isOnline => _isOnline;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _connSub = _connectivity.onConnectivityChanged.listen(_onConnectivity);
    await _onConnectivity(await _connectivity.checkConnectivity());

    if (_config.pingHost != null) {
      _heartbeat = Timer.periodic(
        _config.heartbeatInterval,
        (_) => _probeAndUpdate(),
      );
    }
  }

  Future<void> stop() async {
    _started = false;
    await _connSub?.cancel();
    _connSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  Future<bool> probeNow() => _probeAndUpdate(force: true);

  Future<void> _onConnectivity(List<ConnectivityResult> results) async {
    final hasInterface = results.isNotEmpty &&
        !results.every((r) => r == ConnectivityResult.none);
    if (!hasInterface) {
      _update(false);
      return;
    }
    if (_config.pingHost != null) {
      await _probeAndUpdate();
    } else {
      _update(true);
    }
  }

  Future<bool> _probeAndUpdate({bool force = false}) async {
    final host = _config.pingHost;
    if (host == null) return _isOnline;

    final now = DateTime.now();
    if (!force && now.difference(_lastProbeAt) < _config.cacheWindow) {
      _update(_lastProbeResult);
      return _lastProbeResult;
    }

    bool reachable;
    try {
      final result =
          await InternetAddress.lookup(host).timeout(_config.probeTimeout);
      reachable = result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      reachable = false;
    }

    _lastProbeResult = reachable;
    _lastProbeAt = now;
    _update(reachable);
    return reachable;
  }

  void _update(bool online) {
    if (_isOnline == online) return;
    _isOnline = online;
    if (online) {
      SyncActions.connectionRestored.dispatch();
    } else {
      SyncActions.connectionLost.dispatch();
    }
  }
}
