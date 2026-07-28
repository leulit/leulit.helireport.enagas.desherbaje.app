import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:helireport_desherbaje/presentation/mapa/layers/clustered_marker_layer.dart';

void main() {
  // Regresión del memo de bounds acolchados (FASE 2 de la optimización del
  // mapa): un pan pequeño dentro del colchón NO debe disparar una búsqueda
  // nueva en el índice ni una instancia nueva de `MarkerLayer` — es lo que
  // deja sobrevivir la caché de proyección de `MarkerLayer` entre frames.
  // Salir del colchón (o del zoom entero) SÍ debe rehacer ambas cosas.
  testWidgets(
    'pan dentro del colchón reusa MarkerLayer; pan fuera lo reconstruye',
    (tester) async {
      final mapController = MapController();
      var searchCount = 0;

      Widget buildMap() {
        return MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              mapController: mapController,
              options: const MapOptions(
                initialCenter: LatLng(0, 0),
                initialZoom: 15,
              ),
              children: [
                ClusteredMarkerLayer<LatLng>(
                  points: const [
                    LatLng(0, 0),
                    LatLng(0.0005, 0.0005),
                    LatLng(-0.0005, -0.0005),
                  ],
                  getPosition: (p) => p,
                  buildMarker: (_) => const SizedBox(width: 10, height: 10),
                  markerWidth: (_) => 10,
                  clusterColor: Colors.red,
                  minZoom: 0,
                  onSearchPerformed: () => searchCount++,
                ),
              ],
            ),
          ),
        );
      }

      await tester.pumpWidget(buildMap());
      await tester.pumpAndSettle();

      expect(searchCount, 1, reason: 'primer build siempre busca');
      final firstLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));

      // Bounds acolchados un 35% respecto al visible: un pan del 5% del
      // ancho visible queda holgadamente CONTENIDO en el colchón.
      final visible = mapController.camera.visibleBounds;
      final smallLngShift = (visible.east - visible.west) * 0.05;
      mapController.move(
        LatLng(0, smallLngShift),
        mapController.camera.zoom,
      );
      await tester.pumpAndSettle();

      expect(searchCount, 1,
          reason: 'pan dentro del colchón no debe re-buscar');
      final secondLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
      expect(identical(firstLayer, secondLayer), isTrue,
          reason: 'sin nueva búsqueda debe reusarse la misma instancia');

      // Un pan grande (varias veces el ancho visible) cae fuera del colchón
      // con margen de sobra, sin depender de la geometría exacta del padding.
      final bigLngShift = (visible.east - visible.west) * 5;
      mapController.move(
        LatLng(0, bigLngShift),
        mapController.camera.zoom,
      );
      await tester.pumpAndSettle();

      expect(searchCount, 2, reason: 'salir del colchón debe re-buscar');
      final thirdLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
      expect(identical(firstLayer, thirdLayer), isFalse,
          reason: 'tras re-buscar debe haber una instancia nueva');
    },
  );
}
