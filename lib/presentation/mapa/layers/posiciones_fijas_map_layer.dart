import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'clustered_marker_layer.dart';
import 'point_label_marker.dart';
import 'posiciones_fijas_map_controller.dart';

class PosicionesFijasMapLayer extends StatelessWidget {
  /// Verde claro: el texto de [PointLabelMarker] es negro, así que el relleno
  /// necesita luminosidad alta (el `moduleGreen` del tema deja la etiqueta
  /// ilegible).
  static const Color _fill = Color(0xFF81C784);

  const PosicionesFijasMapLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PosicionFijaMarkerInfo>>(
      valueListenable: Get.find<PosicionesFijasMapController>().marcadores,
      builder: (_, points, __) => ClusteredMarkerLayer<PosicionFijaMarkerInfo>(
        points: points,
        getPosition: (p) => p.point,
        markerWidth: (p) => PointLabelMarker.widthFor(p.label),
        buildMarker: (p) => PointLabelMarker(label: p.label, fill: _fill),
        clusterColor: _fill,
        minZoom: 12,
      ),
    );
  }
}
