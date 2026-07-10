import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_rotation_sensor/flutter_rotation_sensor.dart';
import 'package:geolocator/geolocator.dart';

import '../app_log.dart';

/// Una muestra georreferenciada instantánea: posición GPS + rumbo de la brújula.
///
/// GeoJSON usa orden `[lon, lat]`; aquí se conservan campos nombrados y el
/// builder (`media_gis_geojson.dart`) se encarga del orden al serializar.
class MediaGisSample {
  /// Latitud WGS84 (grados).
  final double lat;

  /// Longitud WGS84 (grados).
  final double lon;

  /// Altitud en metros (si disponible).
  final double? alt;

  /// Azimuth de la brújula 0..360 (`flutter_rotation_sensor`, rad→deg,
  /// normalizado). 0 = norte magnético, 90 = este.
  final double? headingDeg;

  /// Precisión estimada del rumbo en grados (si la aporta el sensor; si no,
  /// null — p.ej. iOS siempre reporta -1 en radianes).
  final double? headingAccuracy;

  /// Rumbo GPS (course over ground) de `geolocator` (`Position.heading`).
  final double? gpsHeading;

  /// Precisión horizontal del fix en metros (`Position.accuracy`).
  final double? accuracyM;

  /// Velocidad en m/s (`Position.speed`).
  final double? speedMps;

  /// Instante de captura, en UTC.
  final DateTime tsUtc;

  const MediaGisSample({
    required this.lat,
    required this.lon,
    required this.tsUtc,
    this.alt,
    this.headingDeg,
    this.headingAccuracy,
    this.gpsHeading,
    this.accuracyM,
    this.speedMps,
  });
}

/// Graba GIS durante la captura de media (foto/vídeo) desde la cámara propia.
///
/// Su ciclo de vida es el de la página de cámara. Abre streams **propios** de
/// posición (`geolocator`, 1 s) y de orientación (`flutter_rotation_sensor`),
/// **independientes** del `GpsBackgroundService` (work-track de jornada): ambos
/// pueden coexistir.
///
/// - Foto → [snapshotPhoto] devuelve los últimos valores en el instante del
///   disparo.
/// - Vídeo → [startTrack]/[stopTrack] recogen una muestra por segundo durante
///   la grabación.
///
/// Si el permiso de ubicación se deniega, queda en **modo sin-GIS**: no lanza,
/// [snapshotPhoto] devuelve `null` y los tracks salen vacíos.
class MediaGisRecorder {
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<OrientationEvent>? _orientationSub;
  Timer? _trackTimer;

  Position? _lastPosition;
  double? _lastHeadingDeg;
  double? _lastHeadingAccuracyDeg;

  List<MediaGisSample>? _track;

  bool _started = false;

  /// Pide permiso `whileInUse` y abre los streams de posición y orientación.
  /// Nunca lanza: si el permiso se deniega, queda en modo sin-GIS.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Orientación (brújula): no requiere permiso. Funciona parado.
    if (RotationSensor.isPlatformSupported) {
      try {
        _orientationSub =
            RotationSensor.orientationStream.listen(_onOrientation, onError: (Object e) {
          AppLog.w('MediaGisRecorder: error stream orientación: $e');
        });
      } catch (e, s) {
        AppLog.w('MediaGisRecorder: no se pudo abrir stream de orientación',
            error: e, stackTrace: s);
      }
    }

    final granted = await _ensurePermissions();
    if (!granted) {
      AppLog.w('MediaGisRecorder: permiso de ubicación denegado → modo sin-GIS');
      return;
    }

    try {
      _positionSub = Geolocator.getPositionStream(
        locationSettings: _locationSettings(),
      ).listen(
        (p) => _lastPosition = p,
        onError: (Object e) => AppLog.w('MediaGisRecorder: error stream GPS: $e'),
      );
    } catch (e, s) {
      AppLog.w('MediaGisRecorder: no se pudo abrir stream de GPS',
          error: e, stackTrace: s);
    }
  }

  /// Últimos valores como una única muestra. `null` si aún no hay fix GPS
  /// (o permiso denegado).
  MediaGisSample? snapshotPhoto() => _buildSample();

  /// Arranca la recolección de muestras (1/seg) para un vídeo.
  void startTrack() {
    _track = <MediaGisSample>[];
    _trackTimer?.cancel();
    // Muestra inmediata (t=0) si ya hay fix, y luego cada segundo.
    _collectSample();
    _trackTimer = Timer.periodic(const Duration(seconds: 1), (_) => _collectSample());
  }

  /// Para la recolección y devuelve las muestras acumuladas (puede ir vacía).
  List<MediaGisSample> stopTrack() {
    _trackTimer?.cancel();
    _trackTimer = null;
    final result = _track ?? const <MediaGisSample>[];
    _track = null;
    return result;
  }

  /// Cancela suscripciones y timer. Idempotente.
  void dispose() {
    _trackTimer?.cancel();
    _trackTimer = null;
    unawaited(_positionSub?.cancel());
    _positionSub = null;
    unawaited(_orientationSub?.cancel());
    _orientationSub = null;
    _track = null;
    _started = false;
  }

  // ─────────────────────────────── Internals ───────────────────────────

  void _onOrientation(OrientationEvent event) {
    // azimuth en radianes [0, 2π): 0 = norte, π/2 = este. → grados 0..360.
    final deg = event.eulerAngles.azimuth * 180.0 / math.pi;
    _lastHeadingDeg = (deg % 360.0 + 360.0) % 360.0;
    // accuracy en radianes; -1 = no disponible (iOS siempre).
    _lastHeadingAccuracyDeg =
        event.accuracy < 0 ? null : event.accuracy * 180.0 / math.pi;
  }

  void _collectSample() {
    final sample = _buildSample();
    if (sample != null) _track?.add(sample);
  }

  MediaGisSample? _buildSample() {
    final p = _lastPosition;
    if (p == null) return null;
    return MediaGisSample(
      lat: p.latitude,
      lon: p.longitude,
      alt: p.altitude,
      headingDeg: _lastHeadingDeg,
      headingAccuracy: _lastHeadingAccuracyDeg,
      gpsHeading: p.heading,
      accuracyM: p.accuracy,
      speedMps: p.speed,
      tsUtc: p.timestamp.toUtc(),
    );
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

  LocationSettings _locationSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );
  }
}
