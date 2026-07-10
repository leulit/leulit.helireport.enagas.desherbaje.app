import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:helireport_desherbaje/core/gis/media_gis_map_geometry.dart';

void main() {
  group('parsePhotoGis', () {
    test('extrae punto y heading', () {
      final json = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [-3.7, 40.4, 650.0],
            },
            'properties': {'kind': 'photo', 'heading': 90.0},
          }
        ],
      });
      final r = parsePhotoGis(json);
      expect(r, isNotNull);
      expect(r!.point.latitude, closeTo(40.4, 1e-9));
      expect(r.point.longitude, closeTo(-3.7, 1e-9));
      expect(r.heading, closeTo(90.0, 1e-9));
    });

    test('fallback a gps_heading si falta heading', () {
      final json = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [-3.7, 40.4],
            },
            'properties': {'kind': 'photo', 'gps_heading': 200.0},
          }
        ],
      });
      expect(parsePhotoGis(json)!.heading, closeTo(200.0, 1e-9));
    });

    test('heading null si no hay ni heading ni gps_heading', () {
      final json = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [-3.7, 40.4],
            },
            'properties': {'kind': 'photo'},
          }
        ],
      });
      expect(parsePhotoGis(json)!.heading, isNull);
    });

    test('json inválido -> null', () {
      expect(parsePhotoGis('not json'), isNull);
      expect(parsePhotoGis('{}'), isNull);
    });
  });

  group('parseVideoGis', () {
    test('LineString -> lista de puntos [lat,lon]', () {
      final json = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [-3.70, 40.40, 650, 10, 1000],
                [-3.71, 40.41, 651, 12, 2000],
              ],
            },
            'properties': {'kind': 'video'},
          }
        ],
      });
      final pts = parseVideoGis(json);
      expect(pts.length, 2);
      expect(pts.first.latitude, closeTo(40.40, 1e-9));
      expect(pts.first.longitude, closeTo(-3.70, 1e-9));
      expect(pts.last.latitude, closeTo(40.41, 1e-9));
    });

    test('Point (1 muestra) -> 1 punto', () {
      final json = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [-3.7, 40.4, 650, 10, 1000],
            },
            'properties': {'kind': 'video'},
          }
        ],
      });
      expect(parseVideoGis(json).length, 1);
    });

    test('json inválido -> vacío', () {
      expect(parseVideoGis('nope'), isEmpty);
    });
  });

  group('destinationPoint', () {
    test('rumbo 90 (este) mueve longitud +, lat ~igual', () {
      final p = destinationPoint(const LatLng(0, 0), 90, 1113.2);
      expect(p.latitude, closeTo(0, 1e-4));
      expect(p.longitude, closeTo(0.01, 1e-3));
    });

    test('rumbo 0 (norte) mueve lat +', () {
      final p = destinationPoint(const LatLng(0, 0), 0, 1113.2);
      expect(p.latitude, closeTo(0.01, 1e-3));
      expect(p.longitude, closeTo(0, 1e-6));
    });
  });

  group('arrowGeometry', () {
    test('shaft arranca en from y head tiene 3 puntos con vértice = tip', () {
      const from = LatLng(40.4, -3.7);
      final a = arrowGeometry(from, 45);
      expect(a.shaft.length, 2);
      expect(a.shaft.first, from);
      expect(a.head.length, 3);
      expect(a.head[1].latitude, closeTo(a.shaft[1].latitude, 1e-9));
      expect(a.head[1].longitude, closeTo(a.shaft[1].longitude, 1e-9));
    });
  });

  group('parseVideoTrack', () {
    test('LineString -> vértices con heading', () {
      final json = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [-3.70, 40.40, 650, 10, 1000],
                [-3.71, 40.41, 651, 12, 2000],
              ],
            },
            'properties': {'kind': 'video'},
          }
        ],
      });
      final track = parseVideoTrack(json);
      expect(track.length, 2);
      expect(track.first.point.latitude, closeTo(40.40, 1e-9));
      expect(track.first.heading, closeTo(10, 1e-9));
      expect(track.last.heading, closeTo(12, 1e-9));
    });

    test('coord sin heading_deg -> heading null', () {
      final json = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [-3.70, 40.40],
                [-3.71, 40.41],
              ],
            },
            'properties': {'kind': 'video'},
          }
        ],
      });
      expect(parseVideoTrack(json).first.heading, isNull);
    });
  });

  group('directionBandPolygon', () {
    List<VideoVertex> track(List<double?> headings) => [
          for (var i = 0; i < headings.length; i++)
            VideoVertex(LatLng(40.40 + i * 0.001, -3.70), headings[i]),
        ];

    test('anillo = 2*n puntos, arranca en la traza', () {
      final t = track([90, 90, 90]);
      final ring = directionBandPolygon(t, widthM: 20);
      expect(ring.length, t.length * 2);
      expect(ring.first, t.first.point);
    });

    test('offset desplazado hacia el rumbo (este -> longitud mayor)', () {
      final t = track([90, 90]);
      final ring = directionBandPolygon(t, widthM: 30);
      // El primer punto del offset (último del anillo) corresponde al primer
      // vértice desplazado al este -> longitud mayor que la traza.
      expect(ring.last.longitude, greaterThan(t.first.point.longitude));
    });

    test('vértices sin rumbo heredan el vecino (banda continua)', () {
      final t = track([null, 90, null]);
      final ring = directionBandPolygon(t, widthM: 20);
      expect(ring.length, t.length * 2);
    });

    test('sin ningún rumbo -> vacío', () {
      expect(directionBandPolygon(track([null, null])), isEmpty);
    });

    test('<2 vértices -> vacío', () {
      expect(directionBandPolygon(track([90])), isEmpty);
    });
  });

  group('simplifyTrack (RDP)', () {
    test('colapsa puntos casi-colineales (jitter) a los extremos', () {
      // Traza recta E-W con jitter sub-métrico en latitud (ruido GPS).
      final t = [
        VideoVertex(const LatLng(40.4000000, -3.7000), 90),
        VideoVertex(const LatLng(40.4000001, -3.7001), 90), // ~1cm de desvío
        VideoVertex(const LatLng(40.3999999, -3.7002), 90),
        VideoVertex(const LatLng(40.4000000, -3.7003), 90),
      ];
      final s = simplifyTrack(t, epsilonM: 4);
      expect(s.length, 2); // solo extremos sobreviven
    });

    test('preserva una esquina real (> epsilon)', () {
      // L: hacia el este y luego hacia el norte; la esquina supera epsilon.
      final t = [
        VideoVertex(const LatLng(40.4000, -3.7000), 90),
        VideoVertex(const LatLng(40.4000, -3.6990), 90), // esquina
        VideoVertex(const LatLng(40.4010, -3.6990), 0),
      ];
      final s = simplifyTrack(t, epsilonM: 4);
      expect(s.length, 3); // la esquina se conserva
    });

    test('<=2 vértices -> se devuelve tal cual', () {
      final t = [
        VideoVertex(const LatLng(40.40, -3.70), 90),
        VideoVertex(const LatLng(40.41, -3.70), 90),
      ];
      expect(simplifyTrack(t).length, 2);
    });
  });

  group('directionBandTrapezoids', () {
    List<VideoVertex> straight(int n, double heading) => [
          for (var i = 0; i < n; i++)
            VideoVertex(LatLng(40.40 + i * 0.001, -3.70), heading),
        ];

    test('n vértices simplificados -> n-1 quads de 4 puntos', () {
      // Traza norte con esquinas reales para que RDP no colapse (usa L largo).
      final t = [
        VideoVertex(const LatLng(40.400, -3.700), 90),
        VideoVertex(const LatLng(40.402, -3.700), 90),
        VideoVertex(const LatLng(40.402, -3.698), 0),
      ];
      final quads = directionBandTrapezoids(t, simplifyEpsilonM: 1);
      expect(quads.length, 2);
      for (final q in quads) {
        expect(q.length, 4);
      }
    });

    test('quads consecutivos comparten la arista [P[i+1], off[i+1]]', () {
      final t = [
        VideoVertex(const LatLng(40.400, -3.700), 90),
        VideoVertex(const LatLng(40.402, -3.700), 90),
        VideoVertex(const LatLng(40.402, -3.698), 0),
      ];
      final quads = directionBandTrapezoids(t, simplifyEpsilonM: 1);
      // quad = [P_i, P_{i+1}, off_{i+1}, off_i]. La arista compartida es
      // P_{i+1} (=quad0[1]==quad1[0]) y off_{i+1} (=quad0[2]==quad1[3]).
      expect(quads[0][1], quads[1][0]);
      expect(quads[0][2], quads[1][3]);
    });

    test('offset a un único lado (traza norte + cámara este -> este)', () {
      final quads = directionBandTrapezoids(straight(3, 90), simplifyEpsilonM: 0);
      // off_i (quad[3]) y off_{i+1} (quad[2]) al este: longitud > traza.
      for (final q in quads) {
        expect(q[3].longitude, greaterThan(q[0].longitude));
        expect(q[2].longitude, greaterThan(q[1].longitude));
      }
    });

    test('sin ningún rumbo -> vacío', () {
      expect(directionBandTrapezoids(straight(3, 0).map((v) =>
          VideoVertex(v.point, null)).toList()), isEmpty);
    });
  });
}
