import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Devuelve true si los segmentos [p1]-[q1] y [p2]-[q2] se intersectan.
///
/// Trata `(longitude, latitude)` como coordenadas cartesianas (x, y).
/// Para líneas cortas a zoom ≥ 12 la distorsión es despreciable.
bool doSegmentsIntersect(LatLng p1, LatLng q1, LatLng p2, LatLng q2) {
  int orientation(LatLng a, LatLng b, LatLng c) {
    final val = (b.latitude - a.latitude) * (c.longitude - b.longitude) -
        (b.longitude - a.longitude) * (c.latitude - b.latitude);
    if (val.abs() < 1e-7) return 0;
    return val > 0 ? 1 : 2;
  }

  bool onSegment(LatLng p, LatLng q, LatLng r) =>
      q.latitude <= math.max(p.latitude, r.latitude) &&
      q.latitude >= math.min(p.latitude, r.latitude) &&
      q.longitude <= math.max(p.longitude, r.longitude) &&
      q.longitude >= math.min(p.longitude, r.longitude);

  final o1 = orientation(p1, q1, p2);
  final o2 = orientation(p1, q1, q2);
  final o3 = orientation(p2, q2, p1);
  final o4 = orientation(p2, q2, q1);

  if (o1 != o2 && o3 != o4) return true;
  if (o1 == 0 && onSegment(p1, p2, q1)) return true;
  if (o2 == 0 && onSegment(p1, q2, q1)) return true;
  if (o3 == 0 && onSegment(p2, p1, q2)) return true;
  if (o4 == 0 && onSegment(p2, q1, q2)) return true;
  return false;
}

/// Punto de intersección entre dos segmentos o null si no existe dentro
/// de ambos, o si son paralelos/coincidentes.
LatLng? getSegmentIntersection(LatLng p1, LatLng p2, LatLng p3, LatLng p4) {
  final x1 = p1.longitude, y1 = p1.latitude;
  final x2 = p2.longitude, y2 = p2.latitude;
  final x3 = p3.longitude, y3 = p3.latitude;
  final x4 = p4.longitude, y4 = p4.latitude;

  final den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
  if (den.abs() < 1e-10) return null;

  final t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den;
  final u = -((x1 - x2) * (y1 - y3) - (y1 - y2) * (x1 - x3)) / den;

  if (t < 0 || t > 1 || u < 0 || u > 1) return null;
  return LatLng(y1 + t * (y2 - y1), x1 + t * (x2 - x1));
}

/// Área con signo: >0 si P está a la izquierda del vector A→B, <0 a la derecha.
double sideOfLine(LatLng a, LatLng b, LatLng p) =>
    (b.longitude - a.longitude) * (p.latitude - a.latitude) -
    (b.latitude - a.latitude) * (p.longitude - a.longitude);
