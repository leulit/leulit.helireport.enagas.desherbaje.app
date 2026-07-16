import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import 'lines_cut_controller.dart';

const Color _line1Color = Color(0xFF2E7D32); // verde
const Color _line2Color = Color(0xFF8E24AA); // morado

/// Construye los layers de flutter_map (polylines + marcadores arrastrables +
/// warning). Devuelve lista vacía si la feature no está activa o el zoom no
/// cumple el umbral — el llamador se encarga de `spread` (`...`) en `children`.
List<Widget> buildLinesCutMapLayers(LinesCutController controller) {
  return [
    // Contenedor reactivo único: un solo Obx que reconstruye el conjunto
    // completo al cambiar cualquier campo del estado.
    _LinesCutReactiveLayers(controller: controller),
  ];
}

class _LinesCutReactiveLayers extends StatelessWidget {
  const _LinesCutReactiveLayers({required this.controller});
  final LinesCutController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.cutStateOn.value || !controller.zoomOk.value) {
        return const SizedBox.shrink();
      }
      final l1 = controller.line1Points.toList();
      final l2 = controller.line2Points.toList();
      final active = controller.activeLine.value;
      final hasErr = controller.hasIntersectionError.value;

      final polylines = <Polyline>[
        if (l1.length == 2)
          Polyline(
            points: l1,
            color: _line1Color,
            strokeWidth: active == 1 ? 4.0 : 3.0,
            borderColor: Colors.white,
            borderStrokeWidth: 1.0,
          ),
        if (l2.length == 2)
          Polyline(
            points: l2,
            color: _line2Color,
            strokeWidth: active == 2 ? 4.0 : 3.0,
            borderColor: Colors.white,
            borderStrokeWidth: 1.0,
          ),
      ];

      final markers = <Marker>[
        for (var i = 0; i < l1.length; i++)
          Marker(
            point: l1[i],
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: _DragCutMarker(
              key: ValueKey('line1_point$i'),
              point: l1[i],
              color: _line1Color,
              pointIndex: i,
              isActive: active == 1,
              onDragEnd: (p) => controller.updatePoint(1, i, p),
            ),
          ),
        for (var i = 0; i < l2.length; i++)
          Marker(
            point: l2[i],
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: _DragCutMarker(
              key: ValueKey('line2_point$i'),
              point: l2[i],
              color: _line2Color,
              pointIndex: i,
              isActive: active == 2,
              onDragEnd: (p) => controller.updatePoint(2, i, p),
            ),
          ),
      ];

      final warningMarker = hasErr && l1.length == 2 && l2.length == 2
          ? Marker(
              point: LatLng(
                (l1[0].latitude +
                        l1[1].latitude +
                        l2[0].latitude +
                        l2[1].latitude) /
                    4,
                (l1[0].longitude +
                        l1[1].longitude +
                        l2[0].longitude +
                        l2[1].longitude) /
                    4,
              ),
              width: 56,
              height: 56,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: const Icon(Icons.warning_rounded,
                    color: Colors.white, size: 28),
              ),
            )
          : null;

      return Stack(
        children: [
          if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
          if (markers.isNotEmpty) MarkerLayer(markers: markers),
          if (warningMarker != null) MarkerLayer(markers: [warningMarker]),
        ],
      );
    });
  }
}

/// Marcador arrastrable implementado con GestureDetector + conversión
/// screen↔CRS del propio flutter_map. Sin dependencias externas.
///
/// Durante el pan se aplica un [Transform.translate] visual (más barato que
/// actualizar la lista Rx en cada frame). Al soltar el dedo se calcula la
/// nueva LatLng y se emite vía [onDragEnd].
class _DragCutMarker extends StatefulWidget {
  const _DragCutMarker({
    super.key,
    required this.point,
    required this.color,
    required this.pointIndex,
    required this.isActive,
    required this.onDragEnd,
  });

  final LatLng point;
  final Color color;
  final int pointIndex;
  final bool isActive;
  final ValueChanged<LatLng> onDragEnd;

  @override
  State<_DragCutMarker> createState() => _DragCutMarkerState();
}

class _DragCutMarkerState extends State<_DragCutMarker> {
  Offset _accumulated = Offset.zero;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        _accumulated = Offset.zero;
        _dragging = true;
      },
      onPanUpdate: (d) {
        setState(() => _accumulated += d.delta);
      },
      onPanEnd: (_) {
        if (!_dragging) return;
        _dragging = false;
        final camera = MapCamera.of(context);
        final base = camera.latLngToScreenOffset(widget.point);
        final target = base + _accumulated;
        final newPos = camera.offsetToCrs(target);
        setState(() => _accumulated = Offset.zero);
        widget.onDragEnd(newPos);
      },
      onPanCancel: () {
        _dragging = false;
        setState(() => _accumulated = Offset.zero);
      },
      child: Transform.translate(
        offset: _accumulated,
        child: Container(
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.isActive ? Colors.white : Colors.grey.shade300,
              width: widget.isActive ? 3 : 2,
            ),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Center(
            child: Text(
              '${widget.pointIndex + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────── Overlay widgets ──────────────────────────────

/// Botón principal de la feature. Label/acción contextuales:
///  · Inactiva            → "Líneas de corte" (activa + canCut)
///  · Activa + líneas OK  → "Aplicar corte"  (abre diálogo)
///  · Activa, no OK       → "Cancelar"       (desactiva + limpia)
class LinesCutModeButton extends StatelessWidget {
  const LinesCutModeButton({
    super.key,
    required this.controller,
    required this.onApplyCut,
  });

  final LinesCutController controller;
  final VoidCallback onApplyCut;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.zoomOk.value) return const SizedBox.shrink();
      final active = controller.cutStateOn.value;
      final ready = active && controller.areLinesCutReady;

      final List<Color> colors;
      final IconData icon;
      final VoidCallback onTap;

      if (!active) {
        colors = [Colors.green.shade400, Colors.green.shade700];
        icon = Icons.content_cut;
        onTap = () {
          controller.toggleFeature();
          controller.canCut.value = true;
          LinesCutTypedActions.startCutAction.dispatch();
        };
      } else if (ready) {
        colors = [Colors.blue.shade400, Colors.blue.shade700];
        icon = Icons.check;
        onTap = () {
          onApplyCut();          
        };
      } else {
        colors = [Colors.purple.shade400, Colors.purple.shade700];
        icon = Icons.close;
        onTap = () {
          controller.toggleFeature();
          //controller.canCut.value = false;
          LinesCutTypedActions.endCutAction.dispatch();
        };
      }

      return Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  "",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Panel de control: selector de línea activa + botones Aplicar / Limpiar.
/// Se muestra solo cuando la feature está activa y el modo dibujo también.
class LinesCutControlPanel extends StatelessWidget {
  const LinesCutControlPanel({
    super.key,
    required this.controller,
  });

  final LinesCutController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.cutStateOn.value || !controller.canCut.value) {
        return const SizedBox.shrink();
      }
      final hasError = controller.hasIntersectionError.value;

      return Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasError ? Colors.red : Colors.grey.shade300,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  controller.statusMessage,
                  style: TextStyle(
                    fontSize: 12,
                    color: hasError ? Colors.red : Colors.grey.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _actionButton(
                icon: Icons.clear_all,
                label: 'Limpiar',
                color: Colors.redAccent,
                onTap: controller.clearAll,
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
