import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'lines_cut_math.dart';
import 'polyline_segment.dart';

/// Extrae segmentos entre dos líneas de corte sobre un conjunto de polylines
/// visibles.
///
/// Para cada polyline:
///   - Si cruza L1 y L2 → tramo entre ambas intersecciones.
///   - Si cruza solo L1 → mitad de la polyline que mira hacia L2.
///   - Si cruza solo L2 → mitad de la polyline que mira hacia L1.
///   - Si no cruza ninguna → se descarta.
List<PolylineSegment> extractSegmentsBetweenCutLines({
  required List<LatLng> line1Points,
  required List<LatLng> line2Points,
  required List<Polyline> visiblePolylines,
  required LoggedUserCtsProvider ctsProvider,
}) {
  if (line1Points.length != 2 || line2Points.length != 2) return const [];

  final l1s = line1Points[0], l1e = line1Points[1];
  final l2s = line2Points[0], l2e = line2Points[1];
  final segments = <PolylineSegment>[];

  for (final polyline in visiblePolylines) {
    final pts = polyline.points;
    if (pts.length < 2) continue;

    LatLng? ix1;
    int? ix1Seg;
    LatLng? ix2;
    int? ix2Seg;

    for (var i = 0; i < pts.length - 1; i++) {
      if (ix1 == null) {
        final x = getSegmentIntersection(pts[i], pts[i + 1], l1s, l1e);
        if (x != null) {
          ix1 = x;
          ix1Seg = i;
        }
      }
      if (ix2 == null) {
        final x = getSegmentIntersection(pts[i], pts[i + 1], l2s, l2e);
        if (x != null) {
          ix2 = x;
          ix2Seg = i;
        }
      }
      if (ix1 != null && ix2 != null) break;
    }

    if (ix1 == null && ix2 == null) continue;

    final List<LatLng> segPts;
    if (ix1 != null && ix2 != null) {
      final s1 = ix1Seg!;
      final s2 = ix2Seg!;
      final startSeg = math.min(s1, s2);
      final endSeg = math.max(s1, s2);
      final startIx = s1 < s2 ? ix1 : ix2;
      final endIx = s1 < s2 ? ix2 : ix1;
      segPts = [
        startIx,
        for (var i = startSeg + 1; i <= endSeg; i++) pts[i],
        endIx,
      ];
    } else if (ix1 != null) {
      segPts = _keepHalfTowardOther(pts, ix1, ix1Seg!, l1s, l1e, l2s, l2e);
    } else {
      segPts =
          _keepHalfTowardOther(pts, ix2!, ix2Seg!, l2s, l2e, l1s, l1e);
    }

    if (segPts.length >= 2) {
      segments.add(PolylineSegment(
        id: DateTime.now().microsecondsSinceEpoch + segments.length,
        points: segPts,
        originalPolyline: polyline,
        ctsProvider: ctsProvider,
      ));
    }
  }
  return segments;
}

List<LatLng> _keepHalfTowardOther(
  List<LatLng> pts,
  LatLng ix,
  int ixSeg,
  LatLng cls,
  LatLng cle,
  LatLng ols,
  LatLng ole,
) {
  final refMid = LatLng(
    (ols.latitude + ole.latitude) / 2,
    (ols.longitude + ole.longitude) / 2,
  );
  final sideRef = sideOfLine(cls, cle, refMid);
  final nextIdx = math.min(ixSeg + 1, pts.length - 1);
  final sideNext = sideOfLine(cls, cle, pts[nextIdx]);

  if ((sideNext >= 0) == (sideRef >= 0)) {
    return [ix, ...pts.sublist(ixSeg + 1)];
  } else {
    return [...pts.sublist(0, ixSeg + 1), ix];
  }
}
