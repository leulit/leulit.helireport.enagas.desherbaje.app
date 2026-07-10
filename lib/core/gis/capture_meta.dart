import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_log.dart';

/// Metadatos del dispositivo y de la app, capturados una sola vez y cacheados.
///
/// Se embeben en el `gis_json` de cada media para trazabilidad
/// (qué dispositivo / versión de app generó la georreferencia).
class CaptureMeta {
  /// `'android' | 'ios' | 'other'`.
  final String os;

  /// Versión del SO: Android `version.release` / iOS `systemVersion`.
  final String osVersion;

  /// Modelo: Android `model` / iOS `utsname.machine` (o `model` si falta).
  final String deviceModel;

  /// Versión de la app: `'${version}+${buildNumber}'` (p.ej. `'1.0.4+104'`).
  final String appVersion;

  const CaptureMeta({
    required this.os,
    required this.osVersion,
    required this.deviceModel,
    required this.appVersion,
  });
}

/// Memoización: se computa una vez y se reutiliza (lectura de plataforma cara).
Future<CaptureMeta>? _cached;

/// Devuelve los [CaptureMeta] del dispositivo/app. Memoizado: la primera llamada
/// lee de plataforma; las siguientes reutilizan el mismo `Future`.
///
/// Nunca lanza: ante error de plataforma cae a valores `'unknown'` y loguea.
Future<CaptureMeta> captureMeta() => _cached ??= _computeCaptureMeta();

Future<CaptureMeta> _computeCaptureMeta() async {
  var os = 'other';
  var osVersion = 'unknown';
  var deviceModel = 'unknown';
  var appVersion = 'unknown';

  final deviceInfo = DeviceInfoPlugin();
  try {
    if (Platform.isAndroid) {
      os = 'android';
      final info = await deviceInfo.androidInfo;
      osVersion = info.version.release;
      deviceModel = info.model;
    } else if (Platform.isIOS) {
      os = 'ios';
      final info = await deviceInfo.iosInfo;
      osVersion = info.systemVersion;
      final machine = info.utsname.machine;
      deviceModel = machine.isNotEmpty ? machine : info.model;
    }
  } catch (e, s) {
    AppLog.w('captureMeta: fallo leyendo device_info_plus',
        error: e, stackTrace: s);
  }

  try {
    final pkg = await PackageInfo.fromPlatform();
    appVersion = '${pkg.version}+${pkg.buildNumber}';
  } catch (e, s) {
    AppLog.w('captureMeta: fallo leyendo package_info_plus',
        error: e, stackTrace: s);
  }

  return CaptureMeta(
    os: os,
    osVersion: osVersion,
    deviceModel: deviceModel,
    appVersion: appVersion,
  );
}
