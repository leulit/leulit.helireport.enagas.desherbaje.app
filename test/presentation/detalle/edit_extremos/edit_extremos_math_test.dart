import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:helireport_desherbaje/presentation/detalle/edit_extremos/edit_extremos_math.dart';

void main() {
  LatLng p(double lat, double lng) => LatLng(lat, lng);

  group('truncatePolylineAt', () {
    final polyline = [p(0, 0), p(0, 1), p(0, 2), p(0, 3)];

    test('same segment returns start and end only', () {
      final result = truncatePolylineAt(
        polyline,
        p(0, 0.2), p(0, 0.8),
        startSegIdx: 0, endSegIdx: 0,
        startT: 0.2, endT: 0.8,
      );
      expect(result, hasLength(2));
      expect(result.first.longitude, closeTo(0.2, 1e-6));
      expect(result.last.longitude, closeTo(0.8, 1e-6));
    });

    test('includes intermediate vertices between segments', () {
      final result = truncatePolylineAt(
        polyline,
        p(0, 0.5), p(0, 2.5),
        startSegIdx: 0, endSegIdx: 2,
        startT: 0.5, endT: 0.5,
      );
      // start + vertex[1] + vertex[2] + end
      expect(result, hasLength(4));
      expect(result.first.longitude, closeTo(0.5, 1e-6));
      expect(result.last.longitude, closeTo(2.5, 1e-6));
    });

    test('reversed orientation auto-corrects so start is first', () {
      final result = truncatePolylineAt(
        polyline,
        p(0, 2.5), p(0, 0.5),
        startSegIdx: 2, endSegIdx: 0,
        startT: 0.5, endT: 0.5,
      );
      expect(result.first.longitude, closeTo(2.5, 1e-6));
      expect(result.last.longitude, closeTo(0.5, 1e-6));
    });

    test('degenerate polyline (less than 2 points) returns start and end', () {
      final result = truncatePolylineAt(
        [p(0, 0)],
        p(0, 0), p(0, 1),
        startSegIdx: 0, endSegIdx: 0,
        startT: 0, endT: 1,
      );
      expect(result, equals([p(0, 0), p(0, 1)]));
    });
  });

  group('projectPointOntoPolyline', () {
    test('returns null for polyline with less than 2 points', () {
      expect(projectPointOntoPolyline(p(0, 0), [p(0, 0)]), isNull);
      expect(projectPointOntoPolyline(p(0, 0), []), isNull);
    });

    test('projects point onto a horizontal segment', () {
      final result = projectPointOntoPolyline(
        p(1, 0.5), // point above midpoint
        [p(0, 0), p(0, 1)],
      );
      expect(result, isNotNull);
      expect(result!.tAlongSegment, closeTo(0.5, 1e-6));
      expect(result.segmentIndex, equals(0));
      expect(result.point.latitude, closeTo(0.0, 1e-6));
      expect(result.point.longitude, closeTo(0.5, 1e-6));
    });

    test('clamps projection to segment start when point is before it', () {
      final result = projectPointOntoPolyline(
        p(0, -1), // before start
        [p(0, 0), p(0, 1)],
      );
      expect(result, isNotNull);
      expect(result!.tAlongSegment, closeTo(0.0, 1e-6));
      expect(result.point.longitude, closeTo(0.0, 1e-6));
    });

    test('clamps projection to segment end when point is past it', () {
      final result = projectPointOntoPolyline(
        p(0, 2), // past end
        [p(0, 0), p(0, 1)],
      );
      expect(result, isNotNull);
      expect(result!.tAlongSegment, closeTo(1.0, 1e-6));
      expect(result.point.longitude, closeTo(1.0, 1e-6));
    });

    test('selects nearest segment in multi-segment polyline', () {
      final result = projectPointOntoPolyline(
        p(1, 2.5), // above second segment
        [p(0, 0), p(0, 1), p(0, 2), p(0, 3)],
      );
      expect(result, isNotNull);
      expect(result!.segmentIndex, equals(2));
    });

    test('distanceMeters is non-negative', () {
      final result = projectPointOntoPolyline(
        p(1, 0.5),
        [p(0, 0), p(0, 1)],
      );
      expect(result!.distanceMeters, greaterThanOrEqualTo(0));
    });
  });

  group('snapToNearestGasoducto', () {
    Polyline poly(List<LatLng> points) =>
        Polyline(points: points);

    test('returns null when no polylines provided', () {
      expect(snapToNearestGasoducto(p(0, 0), []), isNull);
    });

    test('returns null when candidate is beyond maxMeters', () {
      // Point very far from polyline (several degrees away)
      final result = snapToNearestGasoducto(
        p(10, 10),
        [poly([p(0, 0), p(0, 1)])],
        maxMeters: 25,
      );
      expect(result, isNull);
    });

    test('returns nearest hit when candidate is close enough', () {
      // Point slightly above a horizontal segment at equator (tiny offset)
      final result = snapToNearestGasoducto(
        p(0.0001, 0.5), // ~11m above midpoint
        [poly([p(0, 0), p(0, 1)])],
        maxMeters: 50,
      );
      expect(result, isNotNull);
      expect(result!.projection.tAlongSegment, closeTo(0.5, 0.01));
    });

    test('selects closest polyline when multiple candidates', () {
      final near = poly([p(0, 0), p(0, 1)]);
      final far = poly([p(5, 0), p(5, 1)]);
      final result = snapToNearestGasoducto(
        p(0.0001, 0.5),
        [near, far],
        maxMeters: 100,
      );
      expect(result, isNotNull);
      expect(result!.polyline.points.first.latitude, closeTo(0.0, 1e-6));
    });
  });
}
