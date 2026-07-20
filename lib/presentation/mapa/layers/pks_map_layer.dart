import 'package:flutter/material.dart';

import '../../../core/app_di.dart';
import '../../../domain/entities/pk_entity.dart';
import 'clustered_marker_layer.dart';
import 'point_label_marker.dart';

class PksMapLayer extends StatelessWidget {
  static const Color _fill = Color(0xFFFFC107);

  const PksMapLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PkEntity>>(
      valueListenable: AppDI.pksService.pks,
      builder: (_, points, __) => ClusteredMarkerLayer<PkEntity>(
        points: points,
        getPosition: (p) => p.point,
        markerWidth: (p) => PointLabelMarker.widthFor(p.label),
        buildMarker: (p) => PointLabelMarker(label: p.label, fill: _fill),
        clusterColor: _fill,
      ),
    );
  }
}
