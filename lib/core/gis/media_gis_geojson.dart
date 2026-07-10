import 'dart:convert';

import 'capture_meta.dart';
import 'media_gis_recorder.dart';

/// Builders **puros** (sin IO) del `gis_json` (GeoJSON) por media.
///
/// GeoJSON usa orden **`[lon, lat]`** (+ alt). El top-level SIEMPRE es un
/// `FeatureCollection`. Devuelven `null` cuando no hay muestra útil.

/// Construye el GeoJSON de una **foto**: `Point [lon, lat, alt]` + rumbo y
/// extras en `properties`. `null` si [sample] es null.
String? buildPhotoGeoJson(
  MediaGisSample? sample, {
  required int? userId,
  required CaptureMeta meta,
}) {
  if (sample == null) return null;

  final properties = <String, dynamic>{
    'kind': 'photo',
    'heading': sample.headingDeg,
    'heading_accuracy': sample.headingAccuracy,
    'gps_heading': sample.gpsHeading,
    'accuracy_m': sample.accuracyM,
    'altitude_m': sample.alt,
    'speed_mps': sample.speedMps,
    'captured_at': sample.tsUtc.toIso8601String(),
    ..._metaProps(userId, meta),
  };

  final featureCollection = <String, dynamic>{
    'type': 'FeatureCollection',
    'features': [
      <String, dynamic>{
        'type': 'Feature',
        'geometry': <String, dynamic>{
          'type': 'Point',
          'coordinates': _pointCoords(sample),
        },
        'properties': properties,
      },
    ],
  };

  return jsonEncode(featureCollection);
}

/// Construye el GeoJSON de un **vídeo**: `LineString` con coordenada custom
/// `[lon, lat, alt, heading_deg, t_epoch_ms]` por vértice.
///
/// Degradación (D10): 0 muestras → `null`; 1 muestra → geometría `Point`
/// (property `kind` sigue `"video"`); ≥2 → `LineString`.
String? buildVideoGeoJson(
  List<MediaGisSample> samples, {
  required int? userId,
  required CaptureMeta meta,
}) {
  if (samples.isEmpty) return null;

  final properties = <String, dynamic>{
    'kind': 'video',
    'coord_format': const ['lon', 'lat', 'alt', 'heading_deg', 't_epoch_ms'],
    'sample_interval_s': 1,
    'started_at': samples.first.tsUtc.toIso8601String(),
    'ended_at': samples.last.tsUtc.toIso8601String(),
    ..._metaProps(userId, meta),
  };

  final Map<String, dynamic> geometry;
  if (samples.length == 1) {
    geometry = <String, dynamic>{
      'type': 'Point',
      'coordinates': _videoCoord(samples.first),
    };
  } else {
    geometry = <String, dynamic>{
      'type': 'LineString',
      'coordinates': samples.map(_videoCoord).toList(),
    };
  }

  final featureCollection = <String, dynamic>{
    'type': 'FeatureCollection',
    'features': [
      <String, dynamic>{
        'type': 'Feature',
        'geometry': geometry,
        'properties': properties,
      },
    ],
  };

  return jsonEncode(featureCollection);
}

/// `[lon, lat]` o `[lon, lat, alt]` si hay altitud.
List<double> _pointCoords(MediaGisSample s) =>
    s.alt == null ? <double>[s.lon, s.lat] : <double>[s.lon, s.lat, s.alt!];

/// Coordenada custom de vídeo: `[lon, lat, alt, heading_deg, t_epoch_ms]`.
/// `alt`/`heading` pueden ir null; `t_epoch_ms` es epoch ms UTC absoluto.
List<dynamic> _videoCoord(MediaGisSample s) => <dynamic>[
      s.lon,
      s.lat,
      s.alt,
      s.headingDeg,
      s.tsUtc.toUtc().millisecondsSinceEpoch,
    ];

Map<String, dynamic> _metaProps(int? userId, CaptureMeta meta) => <String, dynamic>{
      'user_id': userId,
      'os': meta.os,
      'os_version': meta.osVersion,
      'device_model': meta.deviceModel,
      'app_version': meta.appVersion,
    };
