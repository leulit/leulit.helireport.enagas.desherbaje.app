import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:helireport_desherbaje/presentation/mapa/lines_cut/lines_cut_math.dart';

void main() {
  // Helper
  LatLng p(double lat, double lng) => LatLng(lat, lng);

  group('doSegmentsIntersect', () {
    test('crossing segments return true', () {
      expect(
        doSegmentsIntersect(p(0, -1), p(0, 1), p(-1, 0), p(1, 0)),
        isTrue,
      );
    });

    test('parallel horizontal segments return false', () {
      expect(
        doSegmentsIntersect(p(0, 0), p(0, 2), p(1, 0), p(1, 2)),
        isFalse,
      );
    });

    test('T-intersection at endpoint returns true', () {
      // Segment 2 starts exactly on segment 1
      expect(
        doSegmentsIntersect(p(0, 0), p(0, 2), p(0, 1), p(1, 1)),
        isTrue,
      );
    });

    test('collinear non-overlapping segments return false', () {
      expect(
        doSegmentsIntersect(p(0, 0), p(0, 1), p(0, 2), p(0, 3)),
        isFalse,
      );
    });

    test('collinear overlapping segments return true', () {
      expect(
        doSegmentsIntersect(p(0, 0), p(0, 2), p(0, 1), p(0, 3)),
        isTrue,
      );
    });
  });

  group('getSegmentIntersection', () {
    test('returns intersection point for crossing segments', () {
      final result = getSegmentIntersection(
        p(0, -1), p(0, 1), p(-1, 0), p(1, 0),
      );
      expect(result, isNotNull);
      expect(result!.latitude, closeTo(0.0, 1e-6));
      expect(result.longitude, closeTo(0.0, 1e-6));
    });

    test('returns null for parallel segments', () {
      expect(
        getSegmentIntersection(p(0, 0), p(0, 2), p(1, 0), p(1, 2)),
        isNull,
      );
    });

    test('returns null when segments do not reach each other', () {
      // Extensions would intersect but actual segments do not
      expect(
        getSegmentIntersection(p(0, 0), p(0, 1), p(2, -1), p(2, 1)),
        isNull,
      );
    });
  });

  group('sideOfLine', () {
    test('point to the left of vector A→B returns positive', () {
      final result = sideOfLine(p(0, 0), p(0, 1), p(1, 0));
      expect(result, greaterThan(0));
    });

    test('point to the right of vector A→B returns negative', () {
      final result = sideOfLine(p(0, 0), p(0, 1), p(-1, 0));
      expect(result, lessThan(0));
    });

    test('point on the line returns zero', () {
      final result = sideOfLine(p(0, 0), p(0, 2), p(0, 1));
      expect(result, closeTo(0.0, 1e-9));
    });
  });

}
