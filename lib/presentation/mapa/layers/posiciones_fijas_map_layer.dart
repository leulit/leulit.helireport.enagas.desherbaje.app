import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';

import 'posiciones_fijas_map_controller.dart';

class PosicionesFijasMapLayer extends StatelessWidget {
  final RxDouble currentZoom;

  const PosicionesFijasMapLayer({super.key, required this.currentZoom});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PosicionesFijasMapController>();
    return Obx(() {
      if (currentZoom.value <= 14) return const SizedBox.shrink();
      return MarkerLayer(
        markers: controller.marcadores.map((p) {
          final w = (p.label.length * 7.0 + 24).clamp(56.0, 140.0);
          return Marker(
            point: p.point,
            width: w,
            height: 30,
            alignment: Alignment.bottomCenter,
            child: _PosicionFijaMarker(label: p.label),
          );
        }).toList(),
      );
    });
  }
}

class _PosicionFijaMarker extends StatelessWidget {
  final String label;
  const _PosicionFijaMarker({required this.label});

  static const _fill = Color(0xFFFFC107);
  static const _border = Color(0xFF263238);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _fill,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _border, width: 1),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(0, 1)),
            ],
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.black,
              height: 1.1,
            ),
          ),
        ),
        CustomPaint(
          size: const Size(10, 7),
          painter: _PosicionFijaTrianglePainter(fill: _fill, border: _border),
        ),
      ],
    );
  }
}

class _PosicionFijaTrianglePainter extends CustomPainter {
  final Color fill;
  final Color border;
  const _PosicionFijaTrianglePainter({required this.fill, required this.border});

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _PosicionFijaTrianglePainter old) =>
      old.fill != fill || old.border != border;
}
