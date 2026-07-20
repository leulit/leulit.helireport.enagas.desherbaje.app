import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Etiqueta con pico inferior usada por los marcadores de PK y de hito.
class PointLabelMarker extends StatelessWidget {
  final String label;
  final Color fill;

  static const Color border = Color(0xFF263238);

  const PointLabelMarker({super.key, required this.label, required this.fill});

  /// Ancho que necesita [label] con el estilo de esta etiqueta.
  static double widthFor(String label) =>
      (label.length * 7.0 + 24).clamp(56.0, 140.0);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border, width: 1),
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
          painter: _TrianglePainter(fill: fill, border: border),
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color fill;
  final Color border;
  const _TrianglePainter({required this.fill, required this.border});

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
  bool shouldRepaint(covariant _TrianglePainter old) =>
      old.fill != fill || old.border != border;
}
