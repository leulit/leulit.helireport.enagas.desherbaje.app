import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:helireport_desherbaje/core/gis/capture_meta.dart';
import 'package:helireport_desherbaje/core/gis/media_gis_geojson.dart';
import 'package:helireport_desherbaje/core/gis/media_gis_recorder.dart';

const _meta = CaptureMeta(
  os: 'android',
  osVersion: '14',
  deviceModel: 'Pixel 7',
  appVersion: '1.0.4+104',
);

MediaGisSample _sample({
  double lat = 40.4168,
  double lon = -3.7038,
  double? alt = 650.0,
  double? heading = 123.4,
  double? headingAccuracy = 5.0,
  double? gpsHeading = 0.0,
  double? accuracyM = 4.2,
  double? speedMps = 0.0,
  required DateTime ts,
}) =>
    MediaGisSample(
      lat: lat,
      lon: lon,
      alt: alt,
      headingDeg: heading,
      headingAccuracy: headingAccuracy,
      gpsHeading: gpsHeading,
      accuracyM: accuracyM,
      speedMps: speedMps,
      tsUtc: ts,
    );

void main() {
  final t0 = DateTime.utc(2026, 7, 10, 9, 12, 33);
  final t1 = DateTime.utc(2026, 7, 10, 9, 12, 34);

  group('buildPhotoGeoJson', () {
    test('foto sin sample (galería) emite geometry null + source gallery', () {
      final json = buildPhotoGeoJson(null,
          userId: 42, meta: _meta, source: MediaSource.gallery);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final feature =
          (decoded['features'] as List).first as Map<String, dynamic>;
      final props = feature['properties'] as Map<String, dynamic>;

      expect(feature['geometry'], isNull);
      expect(props['kind'], 'photo');
      expect(props['source'], 'gallery');
    });

    test('builds a FeatureCollection with a Point in [lon, lat, alt] order', () {
      final json = buildPhotoGeoJson(_sample(ts: t0),
          userId: 42, meta: _meta, source: MediaSource.camera);
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['type'], 'FeatureCollection');
      final features = decoded['features'] as List;
      expect(features, hasLength(1));

      final feature = features.first as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>;
      expect(geometry['type'], 'Point');

      final coords = geometry['coordinates'] as List;
      // [lon, lat, alt] — lon FIRST.
      expect(coords[0], -3.7038);
      expect(coords[1], 40.4168);
      expect(coords[2], 650.0);
    });

    test('properties carry kind + source + meta + user_id', () {
      final json = buildPhotoGeoJson(_sample(ts: t0),
          userId: 42, meta: _meta, source: MediaSource.camera);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final props = ((decoded['features'] as List).first
          as Map<String, dynamic>)['properties'] as Map<String, dynamic>;

      expect(props['kind'], 'photo');
      expect(props['source'], 'camera');
      expect(props['user_id'], 42);
      expect(props['os'], 'android');
      expect(props['os_version'], '14');
      expect(props['device_model'], 'Pixel 7');
      expect(props['app_version'], '1.0.4+104');
      expect(props['heading'], 123.4);
      expect(props['captured_at'], t0.toIso8601String());
    });

    test('omits alt from coordinates when null → [lon, lat]', () {
      final json = buildPhotoGeoJson(_sample(alt: null, ts: t0),
          userId: 1, meta: _meta, source: MediaSource.camera);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final coords = (((decoded['features'] as List).first
              as Map<String, dynamic>)['geometry']
          as Map<String, dynamic>)['coordinates'] as List;
      expect(coords, hasLength(2));
      expect(coords[0], -3.7038);
      expect(coords[1], 40.4168);
    });

    test('null user_id is allowed and serialized as null', () {
      final json = buildPhotoGeoJson(_sample(ts: t0),
          userId: null, meta: _meta, source: MediaSource.camera);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final props = ((decoded['features'] as List).first
          as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
      expect(props.containsKey('user_id'), isTrue);
      expect(props['user_id'], isNull);
    });
  });

  group('buildVideoGeoJson', () {
    test('degrade: 0 samples (galería) → geometry null + source gallery', () {
      final json = buildVideoGeoJson(const [],
          userId: 42, meta: _meta, source: MediaSource.gallery);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final feature =
          (decoded['features'] as List).first as Map<String, dynamic>;
      final props = feature['properties'] as Map<String, dynamic>;

      expect(feature['geometry'], isNull);
      expect(props['kind'], 'video');
      expect(props['source'], 'gallery');
    });

    test('degrade: 1 sample → Point geometry, kind stays "video"', () {
      final json = buildVideoGeoJson(
        [_sample(ts: t0)],
        userId: 42,
        meta: _meta,
        source: MediaSource.camera,
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final feature =
          (decoded['features'] as List).first as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final props = feature['properties'] as Map<String, dynamic>;

      expect(geometry['type'], 'Point');
      expect(props['kind'], 'video');

      // Single Point uses the custom 5-tuple coordinate.
      final coord = geometry['coordinates'] as List;
      expect(coord, hasLength(5));
    });

    test('multi-sample → LineString with custom 5-tuple coordinates', () {
      final json = buildVideoGeoJson(
        [
          _sample(lon: -3.7038, lat: 40.4168, alt: 650.0, heading: 120.0, ts: t0),
          _sample(lon: -3.7039, lat: 40.4169, alt: 650.5, heading: 121.5, ts: t1),
        ],
        userId: 42,
        meta: _meta,
        source: MediaSource.camera,
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final feature =
          (decoded['features'] as List).first as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>;

      expect(decoded['type'], 'FeatureCollection');
      expect(geometry['type'], 'LineString');

      final coords = geometry['coordinates'] as List;
      expect(coords, hasLength(2));

      // Coordinate tuple layout: [lon, lat, alt, heading_deg, t_epoch_ms].
      final first = coords.first as List;
      expect(first, hasLength(5));
      expect(first[0], -3.7038); // lon
      expect(first[1], 40.4168); // lat
      expect(first[2], 650.0); // alt
      expect(first[3], 120.0); // heading_deg
      expect(first[4], t0.millisecondsSinceEpoch); // t_epoch_ms (absolute)

      final second = coords[1] as List;
      expect(second[4], t1.millisecondsSinceEpoch);
    });

    test('properties carry coord_format, interval, timespan and meta', () {
      final json = buildVideoGeoJson(
        [_sample(ts: t0), _sample(ts: t1)],
        userId: 7,
        meta: _meta,
        source: MediaSource.camera,
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final props = ((decoded['features'] as List).first
          as Map<String, dynamic>)['properties'] as Map<String, dynamic>;

      expect(props['coord_format'],
          ['lon', 'lat', 'alt', 'heading_deg', 't_epoch_ms']);
      expect(props['sample_interval_s'], 1);
      expect(props['started_at'], t0.toIso8601String());
      expect(props['ended_at'], t1.toIso8601String());
      expect(props['user_id'], 7);
      expect(props['os'], 'android');
      expect(props['os_version'], '14');
      expect(props['device_model'], 'Pixel 7');
      expect(props['app_version'], '1.0.4+104');
    });
  });
}
