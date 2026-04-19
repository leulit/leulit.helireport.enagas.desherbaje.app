import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme.dart';
import '../../domain/entities/actividad_entity.dart';

class ActividadCard extends StatelessWidget {
  final ActividadEntity actividad;
  final VoidCallback? onTap;

  const ActividadCard({super.key, required this.actividad, this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentForEstado(actividad.estado);
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Barra lateral de color
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                  ),
                ),
              ),
              // Contenido
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cabecera
                      /*
                      Row(
                        children: [
                          const Spacer(),
                          Text(
                            actividad.tipoLabel,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF757575),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right,
                              size: 16, color: Color(0xFF757575)),
                        ],
                      ),
                      */
                      const SizedBox(height: 8),
                      // Descripción
                      Text(
                        "Descripción: ${actividad.descripcion}",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Segmentos
                      Row(
                        children: [
                          Icon(Icons.route_outlined,
                              size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            '${actividad.segmentos.length} segmentos',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF757575),
                            ),
                          ),
                        ],
                      ),
                      Divider(color: Colors.grey.shade300, height: 16),
                      // Métricas
                      Row(
                        children: [
                          _MetricChip(
                            icon: Icons.straighten,
                            value:
                                '${actividad.longitudTotal.toStringAsFixed(0)} m',
                          ),
                          const SizedBox(width: 8),
                          _MetricChip(
                            icon: Icons.square_foot,
                            value:
                                '${actividad.superficieM2.toStringAsFixed(0)} m²',
                          ),
                          Spacer(),
                          Row(
                            children: [
                              Icon(Icons.start_rounded,
                                  size: 12, color: Colors.grey.shade500),
                              const SizedBox(width: 3),
                              Text(
                                dateFormat.format(actividad.fechaInicio),
                                style: const TextStyle(fontSize: 11),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.stop_circle_outlined,
                                  size: 12, color: Colors.grey.shade500),
                              const SizedBox(width: 3),
                              Text(
                                dateFormat.format(actividad.fechaFin),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String value;

  const _MetricChip({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: Colors.blueGrey.shade400),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
