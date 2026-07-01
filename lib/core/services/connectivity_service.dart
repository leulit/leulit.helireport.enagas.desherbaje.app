import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../sync/sync_actions.dart';

class ConnectivityService extends GetxService {
  final _isConnected = true.obs;
  final List<VoidCallback> _syncListeners = [];

  bool get isConnected => _isConnected.value;
  Stream<bool> get onConnectivityChanged => _isConnected.stream;

  @override
  Future<void> onInit() async {
    super.onInit();
    // NO bloquear el arranque: registrar el listener (síncrono) y resolver el
    // primer estado en background. `_isConnected` arranca optimista (`true`);
    // se corrige en microsegundos. Antes: `await checkConnectivity()` +
    // `_hasActualInternet()` (DNS 5s) colgaban el splash dentro de allReady().
    Connectivity().onConnectivityChanged.listen(_updateStatus);
    unawaited(_resolveInitialStatus());
  }

  Future<void> _resolveInitialStatus() async {
    final result = await Connectivity().checkConnectivity();
    await _updateStatus(result);
  }

  void addSyncListener(VoidCallback listener) {
    _syncListeners.add(listener);
  }

  void removeSyncListener(VoidCallback listener) {
    _syncListeners.remove(listener);
  }

  Future<void> _updateStatus(List<ConnectivityResult> results) async {
    final wasOffline = !_isConnected.value;
    final hasInterface = results.isNotEmpty &&
        !results.every((r) => r == ConnectivityResult.none);

    // connectivity_plus reporta incorrectamente en simuladores iOS.
    // Verificamos con una resolución DNS real cuando la interfaz parece inactiva.
    if (!hasInterface) {
      _isConnected.value = await _hasActualInternet();
    } else {
      _isConnected.value = true;
    }

    if (wasOffline && _isConnected.value) {
      SyncActions.connectionRestored.dispatch();
      for (final listener in _syncListeners) {
        listener();
      }
    } else if (!wasOffline && !_isConnected.value) {
      SyncActions.connectionLost.dispatch();
    }
  }

  Future<bool> _hasActualInternet() async {
    try {
      final result = await InternetAddress.lookup('enagastool.helireport.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
