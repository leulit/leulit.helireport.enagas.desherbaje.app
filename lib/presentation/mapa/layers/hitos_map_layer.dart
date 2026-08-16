import 'package:flutter/material.dart';

import '../../../core/app_di.dart';
import '../../../domain/entities/hito_entity.dart';
import 'clustered_marker_layer.dart';
import 'point_label_marker.dart';

class HitosMapLayer extends StatelessWidget {
  static const Color _fill = Color(0xFF81D4FA);

  const HitosMapLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<HitoEntity>>(
      valueListenable: AppDI.hitosService.hitos,
      builder: (_, points, _) => ClusteredMarkerLayer<HitoEntity>(
        points: points,
        getPosition: (h) => h.point,
        markerWidth: (h) => PointLabelMarker.widthFor(h.label),
        buildMarker: (h) => PointLabelMarker(label: h.label, fill: _fill),
        clusterColor: _fill,
      ),
    );
  }
}
