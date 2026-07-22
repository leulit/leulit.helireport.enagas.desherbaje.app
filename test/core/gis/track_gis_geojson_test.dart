import 'package:flutter_test/flutter_test.dart';
import 'package:helireport_desherbaje/core/gis/capture_meta.dart';
import 'package:helireport_desherbaje/core/gis/media_gis_geojson.dart';
import 'package:helireport_desherbaje/domain/entities/traza_entity.dart';

const _meta = CaptureMeta(
  os: 'android',
  osVersion: '14',
  deviceModel: 'Pixel 7',
  appVersion: '1.0.4+104',
);

TrazaPunto _p(DateTime t, {double lat = 40.0, double lng = -3.0}) =>
    TrazaPunto(capturedAt: t, lat: lat, lng: lng, altitudeMeters: 100.0);

void main() {
  final base = DateTime.utc(2026, 7, 10, 9, 0, 0);

  group('buildTrackGeoJson', () {
    test('no points → geometry null', () {
      final json = buildTrackGeoJson(
        const [],
        userId: 1,
        meta: _meta,
        trazaClientId: 'c1',
        name: 'Traza test',
        startedAt: base,
      );
      final feature = (json['features'] as List).first as Map<String, dynamic>;
      expect(feature['geometry'], isNull);
    });

    test('single point → no segment survives (needs >=2) → geometry null', () {
      final json = buildTrackGeoJson(
        [_p(base)],
        userId: 1,
        meta: _meta,
        trazaClientId: 'c1',
        name: 'Traza test',
        startedAt: base,
      );
      final feature = (json['features'] as List).first as Map<String, dynamic>;
      expect(feature['geometry'], isNull);
    });

    test('continuous points (<60s gaps) → single MultiLineString segment', () {
      final points = [
        _p(base),
        _p(base.add(const Duration(seconds: 30))),
        _p(base.add(const Duration(seconds: 60))),
      ];
      final json = buildTrackGeoJson(
        points,
        userId: 1,
        meta: _meta,
        trazaClientId: 'c1',
        name: 'Traza test',
        startedAt: base,
      );
      final feature = (json['features'] as List).first as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>;
      expect(geometry['type'], 'MultiLineString');
      final coords = geometry['coordinates'] as List;
      expect(coords, hasLength(1));
      expect((coords.first as List), hasLength(3));
    });

    test('gap >60s splits into a new segment; 1-point segments are dropped',
        () {
      final points = [
        _p(base), // segment A start
        _p(base.add(const Duration(seconds: 10))), // segment A (survives, 2pts)
        _p(base.add(const Duration(seconds: 100))), // isolated (dropped, 1pt)
        _p(base.add(const Duration(seconds: 200))), // segment B start
        _p(base
            .add(const Duration(seconds: 210))), // segment B (survives, 2pts)
        _p(base.add(const Duration(seconds: 300))), // isolated (dropped, 1pt)
      ];
      final json = buildTrackGeoJson(
        points,
        userId: 1,
        meta: _meta,
        trazaClientId: 'c1',
        name: 'Traza test',
        startedAt: base,
      );
      final feature = (json['features'] as List).first as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>;
      expect(geometry['type'], 'MultiLineString');
      final coords = geometry['coordinates'] as List;
      // Only the two 2-point segments survive; the two 1-point segments are dropped.
      expect(coords, hasLength(2));
      expect((coords[0] as List), hasLength(2));
      expect((coords[1] as List), hasLength(2));
    });

    test('coordinate order is [lon, lat, alt, t_epoch_ms]', () {
      final points = [
        _p(base, lat: 40.1, lng: -3.5),
        _p(base.add(const Duration(seconds: 1)))
      ];
      final json = buildTrackGeoJson(
        points,
        userId: 1,
        meta: _meta,
        trazaClientId: 'c1',
        name: 'Traza test',
        startedAt: base,
      );
      final feature = (json['features'] as List).first as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final firstVertex =
          ((geometry['coordinates'] as List).first as List).first as List;
      expect(firstVertex[0], -3.5); // lon
      expect(firstVertex[1], 40.1); // lat
      expect(firstVertex[2], 100.0); // alt
      expect(firstVertex[3], base.millisecondsSinceEpoch); // t_epoch_ms
    });

    test('properties carry kind/traza_client_id/name/coord_format/meta', () {
      final points = [_p(base), _p(base.add(const Duration(seconds: 1)))];
      final endedAt = base.add(const Duration(minutes: 10));
      final json = buildTrackGeoJson(
        points,
        userId: 7,
        meta: _meta,
        trazaClientId: 'c1',
        name: 'Traza de la tarde',
        startedAt: base,
        endedAt: endedAt,
      );
      final feature = (json['features'] as List).first as Map<String, dynamic>;
      final props = feature['properties'] as Map<String, dynamic>;

      expect(props['kind'], 'track');
      expect(props['traza_client_id'], 'c1');
      expect(props['name'], 'Traza de la tarde');
      expect(props['coord_format'], ['lon', 'lat', 'alt', 't_epoch_ms']);
      expect(props['started_at'], base.toUtc().toIso8601String());
      expect(props['ended_at'], endedAt.toUtc().toIso8601String());
      expect(props['user_id'], 7);
      expect(props['os'], 'android');
      expect(props['device_model'], 'Pixel 7');
    });
  });
}
