import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:helireport_desherbaje/presentation/mapa/lines_cut/lines_cut_controller.dart';
import 'package:helireport_desherbaje/presentation/mapa/lines_cut/lines_cut_engine.dart';

void main() {
  // Gasoducto horizontal en lat 0, de lon 0 a lon 1.
  final traza = Polyline(points: [const LatLng(0, 0), const LatLng(0, 1)]);

  group('segmentCrossesAnyPolyline', () {
    test('detecta el cruce', () {
      expect(
        segmentCrossesAnyPolyline(
            const LatLng(-1, 0.5), const LatLng(1, 0.5), [traza]),
        isTrue,
      );
    });

    test('no cruza si queda fuera', () {
      expect(
        segmentCrossesAnyPolyline(
            const LatLng(-1, 2), const LatLng(1, 2), [traza]),
        isFalse,
      );
    });
  });

  group('LinesCutController — línea que no cruza traza', () {
    late LinesCutController c;

    setUp(() {
      c = LinesCutController(
        visiblePolylinesProvider: () => [traza],
        ctsProvider: () => const [],
      );
      c.cutStateOn.value = true;
      c.canCut.value = true;
      c.updateZoom(kLinesCutMinZoom + 1);
    });

    test('L1 fuera de la traza → no lista y lo dice', () {
      c.addPoint(const LatLng(-1, 2));
      c.addPoint(const LatLng(1, 2));
      expect(c.line1CrossesTraza.value, isFalse);
      expect(c.hasValidationError, isTrue);
      expect(c.statusMessage, contains('Línea 1'));
    });

    test('L1 cruza, L2 no → sigue sin estar lista', () {
      c.addPoint(const LatLng(-1, 0.2));
      c.addPoint(const LatLng(1, 0.2));
      c.addPoint(const LatLng(-1, 2));
      c.addPoint(const LatLng(1, 2));
      expect(c.line1CrossesTraza.value, isTrue);
      expect(c.line2CrossesTraza.value, isFalse);
      expect(c.areLinesCutReady, isFalse);
      expect(c.statusMessage, contains('Línea 2'));
    });

    test('ambas cruzan y no se intersectan → lista', () {
      c.addPoint(const LatLng(-1, 0.2));
      c.addPoint(const LatLng(1, 0.2));
      c.addPoint(const LatLng(-1, 0.8));
      c.addPoint(const LatLng(1, 0.8));
      expect(c.areLinesCutReady, isTrue);
      expect(c.hasValidationError, isFalse);
    });
  });
}
