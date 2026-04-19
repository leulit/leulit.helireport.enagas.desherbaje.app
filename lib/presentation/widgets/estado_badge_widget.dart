import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/extensions.dart';
import '../../domain/entities/actividad_entity.dart';

class EstadoBadge extends StatelessWidget {
  final EstadoActividad estado;
  final bool large;

  const EstadoBadge({super.key, required this.estado, this.large = false});

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentForEstado(estado);
    final bg = large ? AppColors.bgForEstado(estado) : accent;
    final textColor = bg.getContrastTextColor();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 10 : 8,
        vertical: large ? 4 : 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(large ? 6 : 20),
      ),
      child: Text(
        estado.etiqueta.toUpperCase(),
        style: TextStyle(
          fontSize: large ? 11 : 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: textColor,
        ),
      ),
    );
  }
}
