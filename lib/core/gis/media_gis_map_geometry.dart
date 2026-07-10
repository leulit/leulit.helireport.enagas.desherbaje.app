import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Parseo puro (sin IO ni widgets) del `gis_json` (GeoJSON) de una media para
/// pintarlo en el mapa. GeoJSON usa orden [lon, lat].

/// Resultado del parseo de una foto: punto de captura + rumbo (grados brújula).
class PhotoGis {
  final LatLng point;

  /// Rumbo de captura en grados 0..360 (norte=0). Null si la media no lo trae.
  final double? heading;

  const PhotoGis(this.point, this.heading);
}

/// Extrae de un `gis_json` de foto el `Point` y el rumbo. Null si el JSON es
/// inválido o no contiene un punto usable. Rumbo: `properties.heading`
/// (brújula) con fallback a `properties.gps_heading`.
PhotoGis? parsePhotoGis(String gisJson) {
  try {
    final fc = jsonDecode(gisJson) as Map<String, dynamic>;
    final features = fc['features'] as List?;
    if (features == null || features.isEmpty) return null;
    final feature = features.first as Map<String, dynamic>;
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    if (geometry == null) return null;
    final coords = geometry['coordinates'] as List?;
    if (coords == null || coords.length < 2) return null;
    final lon = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();
    final props = feature['properties'] as Map<String, dynamic>?;
    double? heading;
    final h = props?['heading'] ?? props?['gps_heading'];
    if (h is num) heading = h.toDouble();
    return PhotoGis(LatLng(lat, lon), heading);
  } catch (_) {
    return null;
  }
}

/// Vértice de la traza de un vídeo: posición + rumbo de cámara en ese instante.
class VideoVertex {
  final LatLng point;

  /// Rumbo de la cámara en grados 0..360 (norte=0). Null si el vértice no lo
  /// trae (coord sin el campo `heading_deg`).
  final double? heading;

  const VideoVertex(this.point, this.heading);
}

/// Extrae la traza de un `gis_json` de vídeo como vértices con rumbo. Coord
/// custom de vídeo: `[lon, lat, alt, heading_deg, t_epoch_ms]`. Soporta
/// geometry `LineString` y `Point`. Vacío si el JSON es inválido.
List<VideoVertex> parseVideoTrack(String gisJson) {
  try {
    final fc = jsonDecode(gisJson) as Map<String, dynamic>;
    final features = fc['features'] as List?;
    if (features == null || features.isEmpty) return const [];
    final feature = features.first as Map<String, dynamic>;
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    if (geometry == null) return const [];
    final type = geometry['type'] as String?;
    final coords = geometry['coordinates'] as List?;
    if (coords == null || coords.isEmpty) return const [];

    double? headingAt(List l) =>
        (l.length > 3 && l[3] is num) ? (l[3] as num).toDouble() : null;

    if (type == 'Point') {
      if (coords.length < 2) return const [];
      final lon = (coords[0] as num).toDouble();
      final lat = (coords[1] as num).toDouble();
      return [VideoVertex(LatLng(lat, lon), headingAt(coords))];
    }
    final track = <VideoVertex>[];
    for (final c in coords) {
      final l = c as List;
      if (l.length < 2) continue;
      final lon = (l[0] as num).toDouble();
      final lat = (l[1] as num).toDouble();
      track.add(VideoVertex(LatLng(lat, lon), headingAt(l)));
    }
    return track;
  } catch (_) {
    return const [];
  }
}

/// Puntos [lat,lon] de la traza de un vídeo (sin rumbo). Fino sobre
/// [parseVideoTrack]. Lista vacía si el JSON es inválido.
List<LatLng> parseVideoGis(String gisJson) =>
    [for (final v in parseVideoTrack(gisJson)) v.point];

const double _earthRadiusM = 6371000.0;

/// Punto destino a [distanceM] metros desde [from] con rumbo [bearingDeg]
/// (grados, norte=0, horario). Fórmula de destino great-circle.
LatLng destinationPoint(LatLng from, double bearingDeg, double distanceM) {
  final theta = bearingDeg * math.pi / 180.0;
  final delta = distanceM / _earthRadiusM;
  final phi1 = from.latitude * math.pi / 180.0;
  final lambda1 = from.longitude * math.pi / 180.0;

  final sinPhi2 = math.sin(phi1) * math.cos(delta) +
      math.cos(phi1) * math.sin(delta) * math.cos(theta);
  final phi2 = math.asin(sinPhi2.clamp(-1.0, 1.0));
  final y = math.sin(theta) * math.sin(delta) * math.cos(phi1);
  final x = math.cos(delta) - math.sin(phi1) * sinPhi2;
  final lambda2 = lambda1 + math.atan2(y, x);

  return LatLng(phi2 * 180.0 / math.pi, lambda2 * 180.0 / math.pi);
}

/// Geometría de una flecha que arranca en [from] y apunta hacia [bearingDeg].
/// Devuelve el asta `[from, tip]` y la cabeza en V `[barbIzq, tip, barbDer]`.
/// [shaftM] = longitud del asta en metros.
({List<LatLng> shaft, List<LatLng> head}) arrowGeometry(
  LatLng from,
  double bearingDeg, {
  double shaftM = 25.0,
}) {
  final tip = destinationPoint(from, bearingDeg, shaftM);
  final headM = shaftM * 0.35;
  final left = destinationPoint(tip, bearingDeg + 150.0, headM);
  final right = destinationPoint(tip, bearingDeg - 150.0, headM);
  return (shaft: [from, tip], head: [left, tip, right]);
}

/// Anillo cerrado de la "banda de dirección" de un vídeo: por cada vértice de
/// [track] desplaza el punto [widthM] metros hacia el rumbo de cámara y cierra
/// el anillo `[traza..., offset invertido]`. Rellenado semitransparente indica
/// hacia dónde apuntaba la cámara a lo largo del recorrido.
///
/// Los vértices sin rumbo heredan el más cercano (relleno hacia delante y
/// atrás) para mantener la banda continua. Vacío si hay <2 vértices o ningún
/// vértice trae rumbo.
List<LatLng> directionBandPolygon(List<VideoVertex> track,
    {double widthM = 10.0}) {
  if (track.length < 2) return const [];

  final headings = List<double?>.generate(track.length, (i) => track[i].heading);
  double? carry;
  for (var i = 0; i < headings.length; i++) {
    carry = headings[i] ?? carry;
    headings[i] = carry;
  }
  carry = null;
  for (var i = headings.length - 1; i >= 0; i--) {
    carry = headings[i] ?? carry;
    headings[i] = carry;
  }
  if (headings.every((h) => h == null)) return const [];

  final offset = <LatLng>[
    for (var i = 0; i < track.length; i++)
      destinationPoint(track[i].point, headings[i]!, widthM),
  ];

  return <LatLng>[
    for (final v in track) v.point,
    for (final p in offset.reversed) p,
  ];
}

// ─────────────────────── Banda por trazos (v2 / robusta) ───────────────────

/// Rumbo inicial (grados, norte=0, horario) del gran círculo de [a] a [b].
double _bearingBetween(LatLng a, LatLng b) {
  final phi1 = a.latitude * math.pi / 180.0;
  final phi2 = b.latitude * math.pi / 180.0;
  final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
  final y = math.sin(dLon) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLon);
  final deg = math.atan2(y, x) * 180.0 / math.pi;
  return (deg + 360.0) % 360.0;
}

/// Diferencia angular con signo en (-180, 180]: `to - from` normalizada.
double _angleDiff(double from, double to) {
  final d = (to - from) % 360.0; // Dart: 0..360 para divisor positivo
  return d > 180.0 ? d - 360.0 : d;
}

/// Distancia perpendicular (metros) del punto [p] al segmento [a]-[b], en un
/// plano local equirectangular centrado en [a] (válido para pocos metros).
double _distPointToSegM(LatLng p, LatLng a, LatLng b) {
  final latRad = a.latitude * math.pi / 180.0;
  double mx(LatLng q) =>
      (q.longitude - a.longitude) * math.pi / 180.0 * math.cos(latRad) *
      _earthRadiusM;
  double my(LatLng q) =>
      (q.latitude - a.latitude) * math.pi / 180.0 * _earthRadiusM;

  final px = mx(p), py = my(p);
  final bx = mx(b), by = my(b);
  final len2 = bx * bx + by * by;
  if (len2 == 0.0) return math.sqrt(px * px + py * py);
  final t = ((px * bx + py * by) / len2).clamp(0.0, 1.0);
  final dx = px - bx * t, dy = py - by * t;
  return math.sqrt(dx * dx + dy * dy);
}

/// Simplifica la traza con Ramer-Douglas-Peucker (tolerancia [epsilonM] en
/// metros), preservando los vértices conservados (con su rumbo). Elimina el
/// jitter de puntos casi-duplicados/retrocesos del GPS que rompe los rumbos.
List<VideoVertex> simplifyTrack(List<VideoVertex> track,
    {double epsilonM = 4.0}) {
  if (track.length <= 2) return List<VideoVertex>.of(track);
  final pts = [for (final v in track) v.point];

  final keep = <int>{0, pts.length - 1};
  void rec(int lo, int hi) {
    if (hi <= lo + 1) return;
    var maxD = 0.0;
    var idx = -1;
    for (var i = lo + 1; i < hi; i++) {
      final d = _distPointToSegM(pts[i], pts[lo], pts[hi]);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (maxD > epsilonM && idx != -1) {
      keep.add(idx);
      rec(lo, idx);
      rec(idx, hi);
    }
  }

  rec(0, pts.length - 1);
  final sorted = keep.toList()..sort();
  return [for (final i in sorted) track[i]];
}

/// Banda de dirección **robusta**: una lista de trapecios (polígonos separados,
/// uno por segmento) que teselan la traza. Cada vértice se desplaza [widthM]
/// metros perpendicular a la tangente local (cuerda `P[i-1]->P[i+1]`), a un
/// único lado (el que miró la cámara de media); quads consecutivos comparten la
/// arista `[P[i+1], offset[i+1]]` → sin huecos.
///
/// Frente a [directionBandPolygon] (v1, un único polígono que se auto-corta con
/// GPS ruidoso): (a) simplifica con RDP [simplifyEpsilonM] antes; (b) emite
/// polígonos separados, así un tramo degenerado no crea agujeros even-odd
/// globales. Vacío si <2 vértices tras simplificar o ningún rumbo.
List<List<LatLng>> directionBandTrapezoids(List<VideoVertex> track,
    {double widthM = 10.0, double simplifyEpsilonM = 4.0}) {
  final simp = simplifyTrack(track, epsilonM: simplifyEpsilonM);
  final n = simp.length;
  if (n < 2) return const [];

  final headings = List<double?>.generate(n, (i) => simp[i].heading);
  double? carry;
  for (var i = 0; i < n; i++) {
    carry = headings[i] ?? carry;
    headings[i] = carry;
  }
  carry = null;
  for (var i = n - 1; i >= 0; i--) {
    carry = headings[i] ?? carry;
    headings[i] = carry;
  }
  if (headings.every((h) => h == null)) return const [];

  final tangent = List<double>.generate(n, (i) {
    if (i == 0) return _bearingBetween(simp[0].point, simp[1].point);
    if (i == n - 1) return _bearingBetween(simp[n - 2].point, simp[n - 1].point);
    return _bearingBetween(simp[i - 1].point, simp[i + 1].point);
  });

  var sideSum = 0.0;
  for (var i = 0; i < n; i++) {
    final h = headings[i];
    if (h != null) sideSum += _angleDiff(tangent[i], h);
  }
  final side = sideSum >= 0 ? 90.0 : -90.0;

  final off = <LatLng>[
    for (var i = 0; i < n; i++)
      destinationPoint(simp[i].point, tangent[i] + side, widthM),
  ];

  return <List<LatLng>>[
    for (var i = 0; i < n - 1; i++)
      [simp[i].point, simp[i + 1].point, off[i + 1], off[i]],
  ];
}
