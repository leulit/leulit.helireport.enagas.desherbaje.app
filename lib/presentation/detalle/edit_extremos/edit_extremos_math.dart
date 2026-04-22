import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Resultado de proyectar un punto sobre un segmento de una polilínea.
///
/// Trata `(longitude, latitude)` como coordenadas cartesianas (x, y) para la
/// proyección, igual que `lines_cut_math.dart`. Para líneas cortas a zoom ≥ 12
/// la distorsión es despreciable. La distancia se recalcula con Haversine
/// usando `latlong2.Distance` para obtener metros reales.
class ProjectionResult {
  const ProjectionResult({
    required this.point,
    required this.segmentIndex,
    required this.tAlongSegment,
    required this.distanceMeters,
  });

  /// Punto proyectado sobre la polilínea (clamped a los extremos del segmento).
  final LatLng point;

  /// Índice del segmento `[polyline[i], polyline[i+1]]` sobre el que cae.
  final int segmentIndex;

  /// Parámetro paramétrico en [0, 1] a lo largo del segmento `segmentIndex`.
  /// 0 = polyline[segmentIndex], 1 = polyline[segmentIndex+1].
  final double tAlongSegment;

  /// Distancia real en metros entre el punto original y el proyectado.
  final double distanceMeters;
}

/// Resultado de [snapToNearestGasoducto]: la polilínea elegida y el resultado
/// de la proyección ortogonal sobre ella.
class NearestGasoductoHit {
  const NearestGasoductoHit({
    required this.polyline,
    required this.projection,
  });

  final Polyline polyline;
  final ProjectionResult projection;
}

const Distance _distance = Distance();

/// Proyecta [p] ortogonalmente sobre la [polyline] y devuelve el punto
/// resultante, el segmento donde cae y la distancia Haversine en metros.
///
/// Devuelve `null` si la polilínea tiene menos de 2 puntos (no hay segmentos).
ProjectionResult? projectPointOntoPolyline(LatLng p, List<LatLng> polyline) {
  if (polyline.length < 2) return null;

  double bestDist = double.infinity;
  LatLng bestPoint = polyline.first;
  int bestIndex = 0;
  double bestT = 0;

  for (int i = 0; i < polyline.length - 1; i++) {
    final a = polyline[i];
    final b = polyline[i + 1];
    final (proj, t) = _projectOnSegment(p, a, b);
    final d = _distance.as(LengthUnit.Meter, p, proj);
    if (d < bestDist) {
      bestDist = d;
      bestPoint = proj;
      bestIndex = i;
      bestT = t;
    }
  }

  return ProjectionResult(
    point: bestPoint,
    segmentIndex: bestIndex,
    tAlongSegment: bestT,
    distanceMeters: bestDist,
  );
}

/// Recorre todas las [polylines] de gasoductos y devuelve la proyección más
/// cercana al [candidate] si queda dentro de [maxMeters]; devuelve `null`
/// para rechazar el drop (el caller puede revertir el drag).
NearestGasoductoHit? snapToNearestGasoducto(
  LatLng candidate,
  List<Polyline> polylines, {
  double maxMeters = 25,
}) {
  NearestGasoductoHit? best;
  for (final poly in polylines) {
    final proj = projectPointOntoPolyline(candidate, poly.points);
    if (proj == null) continue;
    if (best == null ||
        proj.distanceMeters < best.projection.distanceMeters) {
      best = NearestGasoductoHit(polyline: poly, projection: proj);
    }
  }
  if (best == null || best.projection.distanceMeters > maxMeters) return null;
  return best;
}

/// Reconstruye la polilínea truncada entre [start] y [end] a lo largo de la
/// [source] (polilínea del gasoducto), incluyendo los vértices intermedios.
///
/// Se asume que [start] y [end] son proyecciones sobre la misma [source].
/// La orientación se auto-detecta: si [endSegIdx] < [startSegIdx] o
/// (startSegIdx == endSegIdx && endT < startT), la lista se invierte para que
/// el primer elemento sea siempre [start] y el último [end].
List<LatLng> truncatePolylineAt(
  List<LatLng> source,
  LatLng start,
  LatLng end, {
  required int startSegIdx,
  required int endSegIdx,
  required double startT,
  required double endT,
}) {
  if (source.length < 2) return [start, end];

  // Normaliza orientación: trabajar siempre con start "antes" de end.
  final reversed = endSegIdx < startSegIdx ||
      (startSegIdx == endSegIdx && endT < startT);
  final sIdx = reversed ? endSegIdx : startSegIdx;
  final eIdx = reversed ? startSegIdx : endSegIdx;
  final sPt = reversed ? end : start;
  final ePt = reversed ? start : end;

  final result = <LatLng>[sPt];

  if (sIdx == eIdx) {
    // Ambos caen en el mismo segmento: línea recta sin vértices intermedios.
    result.add(ePt);
  } else {
    // Añade los vértices del gasoducto entre sIdx y eIdx (exclusivos del
    // punto inicial, inclusivos hasta source[eIdx]).
    for (int i = sIdx + 1; i <= eIdx; i++) {
      result.add(source[i]);
    }
    result.add(ePt);
  }

  // Si invertimos, devolvemos el resultado en el orden original solicitado
  // por el caller (start primero, end al final).
  if (reversed) {
    return result.reversed.toList(growable: false);
  }
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Proyección ortogonal de [p] sobre el segmento [a]-[b], clamped a [0, 1].
/// Trata lon/lat como x/y cartesianas.
(LatLng, double) _projectOnSegment(LatLng p, LatLng a, LatLng b) {
  final ax = a.longitude, ay = a.latitude;
  final bx = b.longitude, by = b.latitude;
  final px = p.longitude, py = p.latitude;

  final dx = bx - ax;
  final dy = by - ay;
  final lenSq = dx * dx + dy * dy;

  if (lenSq < 1e-14) {
    // Segmento degenerado (a == b): devuelve el propio extremo.
    return (a, 0);
  }

  double t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
  if (t < 0) t = 0;
  if (t > 1) t = 1;

  return (LatLng(ay + t * dy, ax + t * dx), t);
}
