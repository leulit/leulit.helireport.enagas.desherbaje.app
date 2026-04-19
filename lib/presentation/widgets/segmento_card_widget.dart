import 'package:flutter/material.dart';
import '../../domain/entities/segmento_entity.dart';

class SegmentoCard extends StatelessWidget {
  final SegmentoEntity segmento;
  final int index;
  final Color accentColor;
  final VoidCallback? onTap;

  const SegmentoCard({
    super.key,
    required this.segmento,
    required this.index,
    required this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accentColor.withValues(alpha: 0.15),
          child: Text(
            '${index + 1}',
            style:
                TextStyle(color: accentColor, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(segmento.displayName),
        subtitle: Text('${segmento.longitudKm.toStringAsFixed(2)} km'),
        onTap: onTap,
      ),
    );
  }
}
