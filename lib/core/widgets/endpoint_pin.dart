import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Tamaño de la caja del pin. La punta cae en [kEndpointPinAnchor].
const Size kEndpointPinSize = Size(48, 64);

/// Punto real (geográfico) dentro de la caja: el borde inferior, es decir la
/// punta del pin. Un `Marker` que lo use debe alinearse a `topCenter`.
const Offset kEndpointPinAnchor = Offset(24, 64);

/// Colores canónicos de los extremos del segmento. Verde = inicio, rojo = fin,
/// misma pareja en el mapa del detalle y en el diálogo de editar extremos:
/// un solo vocabulario visual para los mismos dos puntos.
const Color kColorInicio = AppColors.moduleGreen;
final Color kColorFin = Colors.red.shade700;

/// Letra que distingue cada extremo. Va DENTRO del bulbo del pin y repetida en
/// el botón de ruta correspondiente. Existe porque verde/rojo es justo el par
/// que no separa el ~8% de hombres con deficiencia rojo-verde, y esto es una
/// app de campo: el color casa botón y marcador de un vistazo, la letra lo
/// hace independiente del color.
const String kLetraInicio = 'I';
const String kLetraFin = 'F';

/// Pin lágrima con punta abajo, del color del extremo y con su letra en el
/// bulbo.
class EndpointPinPainter extends CustomPainter {
  const EndpointPinPainter({required this.color, required this.letra});

  final Color color;

  /// `null` pinta el punto blanco de realce en vez de una letra — lo que hace
  /// falta cuando el pin no representa un extremo con identidad propia.
  final String? letra;

  @override
  void paint(Canvas canvas, Size size) {
    const bulb = Offset(24, 18);
    const r = 16.0;
    const tip = kEndpointPinAnchor;

    // Silueta lágrima: dos tangentes desde la punta al círculo del bulbo +
    // arco mayor por encima.
    final d = (tip - bulb).distance;
    final baseAngle = math.atan2(tip.dy - bulb.dy, tip.dx - bulb.dx);
    final alpha = math.acos(r / d);
    final a1 = baseAngle - alpha;
    final a2 = baseAngle + alpha;
    final p1 = Offset(bulb.dx + r * math.cos(a1), bulb.dy + r * math.sin(a1));

    final path = ui.Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(p1.dx, p1.dy)
      ..arcTo(
        Rect.fromCircle(center: bulb, radius: r),
        a1,
        -(2 * math.pi - (a2 - a1)), // arco mayor: por encima del bulbo
        false,
      )
      ..lineTo(tip.dx, tip.dy)
      ..close();

    canvas.drawShadow(path, Colors.black54, 3, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );

    final l = letra;
    if (l == null) {
      canvas.drawCircle(bulb, 4.5, Paint()..color = Colors.white);
      return;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: l,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, bulb - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(EndpointPinPainter old) =>
      old.color != color || old.letra != letra;
}

/// Pin estático (no arrastrable) para marcar un extremo del segmento.
class EndpointPin extends StatelessWidget {
  const EndpointPin({super.key, required this.color, required this.letra});

  final Color color;
  final String letra;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: kEndpointPinSize,
        painter: EndpointPinPainter(color: color, letra: letra),
      );
}

/// Insignia circular con la letra del extremo, para repetirla dentro del botón
/// de ruta y que el operador case botón y marcador sin depender del color.
class EndpointLetterBadge extends StatelessWidget {
  const EndpointLetterBadge({super.key, required this.letra});

  final String letra;

  @override
  Widget build(BuildContext context) => Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Text(
          letra,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      );
}
