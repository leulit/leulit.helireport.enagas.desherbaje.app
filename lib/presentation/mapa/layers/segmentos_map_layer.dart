import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:leulit_flutter_fullresponsive/leulit_flutter_fullreponsive.dart';

import '../../../domain/entities/segmento_entity.dart';
import 'segmentos_map_controller.dart';

class SegmentosMapLayer extends GetView<SegmentosMapController> {
  /// `true` cuando el zoom supera el umbral de etiquetas (z > 12). Solo
  /// notifica al CRUZAR el umbral, no por frame (a diferencia del `RxDouble`
  /// de zoom que usaba antes, que reconstruía este layer en cada frame de un
  /// gesto de zoom aunque el umbral no cambiase).
  final ValueNotifier<bool> mostrarLabelsSegmento;

  const SegmentosMapLayer({super.key, required this.mostrarLabelsSegmento});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<int>(
          // Único observable leído: cubre estado+tipo+ct (ver
          // `SegmentosMapController.filterVersion`) — antes esto era un `Obx`
          // que solo leía `rxEstado`/`rxTipo` y el cambio de CT no repintaba
          // las polilíneas.
          valueListenable: controller.filterVersion,
          builder: (context, _, __) {
            return GestureDetector(
              onTap: controller.onPolylineTap,
              child: PolylineLayer<SegmentoEntity>(
                hitNotifier: controller.segmentosHitNotifier,
                polylines: controller.filteredSegmentos
                    .map((s) => Polyline<SegmentoEntity>(
                          points: s.points,
                          color: s.color,
                          strokeWidth: 5.0,
                          borderColor: Colors.white,
                          borderStrokeWidth: 1.0,
                          hitValue: s.segmento,
                        ))
                    .toList(),
              ),
            );
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: mostrarLabelsSegmento,
          builder: (context, mostrar, _) {
            if (!mostrar) return const SizedBox.shrink();
            return ValueListenableBuilder<int>(
              valueListenable: controller.filterVersion,
              builder: (context, _, __) {
                return MarkerLayer(
                  markers: controller.filteredSegmentos
                      .map((s) => Marker(
                            point: s.centroid,
                            width: 0.2.w,
                            height: 32,
                            child: _SegmentoLabel(
                              segmentoInfo: s,
                              onTap: () =>
                                  controller.navigateToSegmento(s.segmento),
                            ),
                          ))
                      .toList(),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _SegmentoLabel extends StatelessWidget {
  final SegmentoMapInfo segmentoInfo;
  final VoidCallback onTap;

  const _SegmentoLabel({required this.segmentoInfo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = segmentoInfo.color;
    final longKm = segmentoInfo.longitudKm;
    final label = longKm >= 1
        ? '${longKm.toStringAsFixed(2)} km'
        : '${(longKm * 1000).toStringAsFixed(0)} m';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 1),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
