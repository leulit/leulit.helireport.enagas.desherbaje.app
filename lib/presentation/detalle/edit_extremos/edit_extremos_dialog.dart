
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/app_di.dart';
import '../../../core/app_theme.dart';
import '../../../core/widgets/endpoint_pin.dart';
import '../../../core/widgets/my_current_location_layer.dart';
import '../../../core/widgets/orto_tile_layers.dart';
import '../../../domain/entities/segmento_entity.dart';
import 'edit_extremos_controller.dart';

/// Diálogo casi a pantalla completa que permite al usuario arrastrar los
/// extremos (A/B) del segmento sobre el mapa con snap al gasoducto más
/// cercano. Devuelve la [SegmentoEntity] actualizada vía `Get.back(result:)`
/// si el usuario guarda, o `null` si cancela.
class EditExtremosDialog extends StatefulWidget {
  const EditExtremosDialog({super.key, required this.segmento});

  final SegmentoEntity segmento;

  @override
  State<EditExtremosDialog> createState() => _EditExtremosDialogState();
}

class _EditExtremosDialogState extends State<EditExtremosDialog> {
  static const String _tag = 'edit_extremos';

  late final EditExtremosController controller;
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      EditExtremosController(original: widget.segmento),
      tag: _tag,
    );
  }

  @override
  void dispose() {
    Get.delete<EditExtremosController>(tag: _tag);
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cam = controller.initialCamera;
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _Header(onClose: controller.cancelar),
          Expanded(
            child: Stack(
              children: [
                Obx(() {
                  return FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCameraFit: controller.initialCameraFit,
                      initialCenter: cam.center,
                      initialZoom: cam.zoom,
                      minZoom: 7,
                      maxZoom: 20,
                      interactionOptions: InteractionOptions(
                        flags: controller.isDraggingMarker.value
                            ? InteractiveFlag.all & ~InteractiveFlag.drag
                            : InteractiveFlag.all,
                      ),
                    ),
                    children: [
                      ...buildOrtoTileLayers(),
                      PolylineLayer(
                        polylines: AppDI.gasoductosService.polylines.toList(),
                      ),
                      PolylineLayer(polylines: [
                        Polyline(
                          points: controller.ubicacionGisDraft.toList(),
                          color: Colors.red,
                          strokeWidth: 6,
                          borderColor: Colors.white,
                          borderStrokeWidth: 2,
                        ),
                      ]),
                      MyCurrentLocationLayer(),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: controller.inicio.value,
                            width: 48,
                            height: 64,
                            alignment: Alignment.topCenter,
                            child: _DragEndpointMarker(
                              kind: EndpointKind.inicio,
                              point: controller.inicio.value,
                              color: controller.colorFor(EndpointKind.inicio),
                              revertTick: controller.revertTick.value,
                              onDragStart: () =>
                                  controller.isDraggingMarker.value = true,
                              onDragEnd: (p) {
                                controller.isDraggingMarker.value = false;
                                controller.onDragEnd(EndpointKind.inicio, p);
                              },
                              onDragCancel: () =>
                                  controller.isDraggingMarker.value = false,
                            ),
                          ),
                          Marker(
                            point: controller.fin.value,
                            width: 48,
                            height: 64,
                            alignment: Alignment.topCenter,
                            child: _DragEndpointMarker(
                              kind: EndpointKind.fin,
                              point: controller.fin.value,
                              color: controller.colorFor(EndpointKind.fin),
                              revertTick: controller.revertTick.value,
                              onDragStart: () =>
                                  controller.isDraggingMarker.value = true,
                              onDragEnd: (p) {
                                controller.isDraggingMarker.value = false;
                                controller.onDragEnd(EndpointKind.fin, p);
                              },
                              onDragCancel: () =>
                                  controller.isDraggingMarker.value = false,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }),
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: _SnapBanner(controller: controller),
                ),
              ],
            ),
          ),
          _ActionBar(controller: controller),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.moduleGreen,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_location_alt_outlined, color: Colors.white),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Editar extremos',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: onClose,
            tooltip: 'Cancelar',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Snap banner (aparece solo cuando hay error)
// ─────────────────────────────────────────────────────────────────────────────

class _SnapBanner extends StatelessWidget {
  const _SnapBanner({required this.controller});
  final EditExtremosController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final err = controller.snapError.value;
      if (err.isEmpty) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Arrastra los extremos (verde: inicio, rojo: fin) sobre el gasoducto',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        );
      }
      return Material(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  err,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action bar (Cancelar / Guardar)
// ─────────────────────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.controller});
  final EditExtremosController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: controller.cancelar,
              child: const Text('Cancelar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Obx(() => ElevatedButton.icon(
                  onPressed:
                      controller.isSaving.value ? null : controller.guardar,
                  icon: controller.isSaving.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Guardar'),
                )),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Marker arrastrable (adaptación de _DragCutMarker de lines_cut_ui.dart).
// Al soltar, si el controller rechaza el drop (snapError != ''), incrementa
// `revertTick` y este widget reinicia su offset acumulado para que el marker
// vuelva visualmente a la posición oficial del controller.
// ─────────────────────────────────────────────────────────────────────────────

class _DragEndpointMarker extends StatefulWidget {
  const _DragEndpointMarker({
    required this.kind,
    required this.point,
    required this.color,
    required this.revertTick,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  final EndpointKind kind;
  final LatLng point;
  final Color color;
  final int revertTick;
  final VoidCallback onDragStart;
  final ValueChanged<LatLng> onDragEnd;
  final VoidCallback onDragCancel;

  @override
  State<_DragEndpointMarker> createState() => _DragEndpointMarkerState();
}

class _DragEndpointMarkerState extends State<_DragEndpointMarker> {
  Offset _accumulated = Offset.zero;
  Offset? _startLocal;
  int _activePointer = -1;
  int _lastRevertTick = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _lastRevertTick = widget.revertTick;
  }

  @override
  void didUpdateWidget(covariant _DragEndpointMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revertTick != _lastRevertTick) {
      _lastRevertTick = widget.revertTick;
      if (_accumulated != Offset.zero) {
        setState(() => _accumulated = Offset.zero);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Usa Listener (raw pointer events) en vez de GestureDetector.pan para
    // que el mapa no gane el gesto en el gesture arena.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (_activePointer != -1) return;
        _activePointer = event.pointer;
        _startLocal = event.localPosition;
        _accumulated = Offset.zero;
        setState(() => _dragging = true);
        widget.onDragStart();
      },
      onPointerMove: (event) {
        if (event.pointer != _activePointer || _startLocal == null) return;
        setState(() => _accumulated = event.localPosition - _startLocal!);
      },
      onPointerUp: (event) {
        if (event.pointer != _activePointer) return;
        _activePointer = -1;
        _startLocal = null;
        final camera = MapCamera.of(context);
        final base = camera.latLngToScreenOffset(widget.point);
        final target = base + _accumulated;
        final newPos = camera.offsetToCrs(target);
        setState(() {
          _accumulated = Offset.zero;
          _dragging = false;
        });
        widget.onDragEnd(newPos);
      },
      onPointerCancel: (event) {
        if (event.pointer != _activePointer) return;
        _activePointer = -1;
        _startLocal = null;
        setState(() {
          _accumulated = Offset.zero;
          _dragging = false;
        });
        widget.onDragCancel();
      },
      // El punto real es el borde inferior (bottom-center) de la caja: en
      // reposo, la punta del pin; en drag, el centro de la mirilla. El bulbo/
      // agarre queda por encima, así el dedo nunca tapa el punto.
      child: Transform.translate(
        offset: _accumulated,
        child: OverflowBox(
          // La mirilla pinta fuera de la caja 48×64; no la recortes.
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: double.infinity,
          child: CustomPaint(
            size: const Size(48, 64),
            painter: _dragging
                ? _CrosshairPainter(color: widget.color)
                : EndpointPinPainter(
                    color: widget.color,
                    letra: widget.kind == EndpointKind.inicio
                        ? kLetraInicio
                        : kLetraFin,
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painters — el punto real es SIEMPRE bottom-center de la caja (24, 64):
// en reposo la punta del pin; en drag el centro de la mirilla.
// ─────────────────────────────────────────────────────────────────────────────

/// Mirilla tipo visor centrada en [kEndpointPinAnchor]. Pinta fuera de la caja: como el
/// dedo agarra el bulbo (parte alta), el centro queda ~30px por debajo del dedo
/// y siempre visible.
class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter({required this.color});

  final Color color;

  static const double _ring = 22;
  static const double _gap =
      24; // hueco > anillo: brazos solo por fuera, interior limpio
  static const double _arm = 40;

  void _reticle(Canvas canvas, Offset c, Paint paint) {
    canvas.drawCircle(c, _ring, paint);
    // Cuatro brazos con hueco central.
    canvas.drawLine(
        Offset(c.dx - _arm, c.dy), Offset(c.dx - _gap, c.dy), paint);
    canvas.drawLine(
        Offset(c.dx + _gap, c.dy), Offset(c.dx + _arm, c.dy), paint);
    canvas.drawLine(
        Offset(c.dx, c.dy - _arm), Offset(c.dx, c.dy - _gap), paint);
    canvas.drawLine(
        Offset(c.dx, c.dy + _gap), Offset(c.dx, c.dy + _arm), paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const c = kEndpointPinAnchor;

    // Halo blanco (trazo grueso) debajo para contraste sobre la línea roja.
    _reticle(
      canvas,
      c,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );
    // Trazo de color encima.
    _reticle(
      canvas,
      c,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    // Punto central exacto.
    canvas.drawCircle(c, 4, Paint()..color = Colors.white);
    canvas.drawCircle(c, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) => old.color != color;
}
