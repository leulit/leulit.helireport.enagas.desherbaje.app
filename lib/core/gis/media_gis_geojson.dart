import 'dart:convert';

import '../../domain/entities/traza_entity.dart';
import 'capture_meta.dart';
import 'media_gis_recorder.dart';

/// Builders **puros** (sin IO) del `gis_json` (GeoJSON) por media.
///
/// GeoJSON usa orden **`[lon, lat]`** (+ alt). El top-level SIEMPRE es un
/// `FeatureCollection`. Siempre devuelven un `String` (FeatureCollection);
/// `geometry` es `null` cuando no hay muestra útil (p.ej. media de galería).

/// Origen de una media: capturada por la cámara de la app o elegida de la
/// galería del dispositivo. Se serializa en `properties.source` del gis_json.
enum MediaSource {
  camera('camera'),
  gallery('gallery');

  const MediaSource(this.wireValue);

  /// Valor tal cual viaja en el gis_json / backend.
  final String wireValue;
}

/// Construye el GeoJSON de una **foto**. Con [sample] → `Point [lon, lat, alt]`
/// + rumbo/extras; sin sample (galería o captura sin fix) → `geometry: null`.
/// Siempre incluye `kind`, `source` y la meta en `properties`.
String buildPhotoGeoJson(
  MediaGisSample? sample, {
  required int? userId,
  required CaptureMeta meta,
  required MediaSource source,
}) {
  final properties = <String, dynamic>{
    'kind': 'photo',
    'source': source.wireValue,
    if (sample != null) ...<String, dynamic>{
      'heading': sample.headingDeg,
      'heading_accuracy': sample.headingAccuracy,
      'gps_heading': sample.gpsHeading,
      'accuracy_m': sample.accuracyM,
      'altitude_m': sample.alt,
      'speed_mps': sample.speedMps,
      'captured_at': sample.tsUtc.toIso8601String(),
    },
    ..._metaProps(userId, meta),
  };

  final featureCollection = <String, dynamic>{
    'type': 'FeatureCollection',
    'features': [
      <String, dynamic>{
        'type': 'Feature',
        'geometry': sample == null
            ? null
            : <String, dynamic>{
                'type': 'Point',
                'coordinates': _pointCoords(sample),
              },
        'properties': properties,
      },
    ],
  };

  return jsonEncode(featureCollection);
}

/// Construye el GeoJSON de un **vídeo**. ≥2 muestras → `LineString`; 1 → `Point`;
/// 0 (galería / sin fix) → `geometry: null`. Siempre incluye `kind`, `source` y
/// meta. Coordenada custom `[lon, lat, alt, heading_deg, t_epoch_ms]` por vértice.
String buildVideoGeoJson(
  List<MediaGisSample> samples, {
  required int? userId,
  required CaptureMeta meta,
  required MediaSource source,
}) {
  final properties = <String, dynamic>{
    'kind': 'video',
    'source': source.wireValue,
    if (samples.isNotEmpty) ...<String, dynamic>{
      'coord_format': const ['lon', 'lat', 'alt', 'heading_deg', 't_epoch_ms'],
      'sample_interval_s': 1,
      'started_at': samples.first.tsUtc.toIso8601String(),
      'ended_at': samples.last.tsUtc.toIso8601String(),
    },
    ..._metaProps(userId, meta),
  };

  final Map<String, dynamic>? geometry;
  if (samples.isEmpty) {
    geometry = null;
  } else if (samples.length == 1) {
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

Map<String, dynamic> _metaProps(int? userId, CaptureMeta meta) =>
    <String, dynamic>{
      'user_id': userId,
      'os': meta.os,
      'os_version': meta.osVersion,
      'device_model': meta.deviceModel,
      'app_version': meta.appVersion,
    };

/// Gap, in seconds, above which two consecutive [TrazaPunto]s are split into
/// separate `MultiLineString` segments.
const int _trackSegmentGapSeconds = 60;

/// Construye el GeoJSON de una **traza** (track GPS manual). Devuelve el
/// `FeatureCollection` ya decodificado como `Map` (no `String`) porque el
/// adaptador lo envía tal cual como body de la petición.
///
/// [points] se asume ordenada ascendentemente por `capturedAt` (así los
/// devuelve `TrazaLocalStore`); se re-ordena defensivamente por si acaso.
/// Se corta en un segmento nuevo cuando el hueco entre dos puntos
/// consecutivos supera [_trackSegmentGapSeconds]; los segmentos resultantes
/// de un único punto se descartan. Sin ningún segmento superviviente →
/// `geometry: null`.
Map<String, dynamic> buildTrackGeoJson(
  List<TrazaPunto> points, {
  required int? userId,
  required CaptureMeta meta,
  required String trazaClientId,
  required String name,
  required DateTime startedAt,
  DateTime? endedAt,
}) {
  final sorted = List<TrazaPunto>.of(points)
    ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

  final segments = <List<TrazaPunto>>[];
  var current = <TrazaPunto>[];
  for (final p in sorted) {
    if (current.isNotEmpty &&
        p.capturedAt.difference(current.last.capturedAt).inSeconds.abs() >
            _trackSegmentGapSeconds) {
      segments.add(current);
      current = <TrazaPunto>[];
    }
    current.add(p);
  }
  if (current.isNotEmpty) segments.add(current);

  final survivingSegments =
      segments.where((s) => s.length >= 2).toList(growable: false);

  final properties = <String, dynamic>{
    'kind': 'track',
    'traza_client_id': trazaClientId,
    'name': name,
    'started_at': startedAt.toUtc().toIso8601String(),
    if (endedAt != null) 'ended_at': endedAt.toUtc().toIso8601String(),
    'coord_format': const [
      'lon',
      'lat',
      'alt',
      't_epoch_ms',
      'accuracy_m',
      'speed_mps',
    ],
    ..._metaProps(userId, meta),
  };

  final Map<String, dynamic>? geometry = survivingSegments.isEmpty
      ? null
      : <String, dynamic>{
          'type': 'MultiLineString',
          'coordinates': survivingSegments
              .map((segment) => segment.map(_trackCoord).toList())
              .toList(),
        };

  return <String, dynamic>{
    'type': 'FeatureCollection',
    'features': [
      <String, dynamic>{
        'type': 'Feature',
        'geometry': geometry,
        'properties': properties,
      },
    ],
  };
}

/// Coordenada de traza: `[lon, lat, alt, t_epoch_ms, accuracy_m, speed_mps]`.
/// `alt`, `accuracy_m` y `speed_mps` pueden ir null (el GPS no siempre los da);
/// `t_epoch_ms` es epoch ms UTC absoluto.
///
/// `accuracy_m` y `speed_mps` viajan porque el punto local se borra tras
/// sincronizar (`TrazaLocalStore.deleteSynced`): lo que no salga aquí no se
/// puede reconstruir después. `accuracy_m` es lo que permite distinguir en el
/// visor un desvío real del operador de un salto de GPS.
List<dynamic> _trackCoord(TrazaPunto p) => <dynamic>[
      p.lng,
      p.lat,
      p.altitudeMeters,
      p.capturedAt.toUtc().millisecondsSinceEpoch,
      p.accuracyMeters,
      p.speedMps,
    ];
