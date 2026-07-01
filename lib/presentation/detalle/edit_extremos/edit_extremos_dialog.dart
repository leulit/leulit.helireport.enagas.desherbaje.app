import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/app_di.dart';
import '../../../core/app_theme.dart';
import '../../../core/widgets/my_current_location_layer.dart';
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
                      TileLayer(
                        urlTemplate: 'https://www.ign.es/wmts/pnoa-ma?'
                            'SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
                            '&LAYER=OI.OrthoimageCoverage&STYLE=default'
                            '&TILEMATRIXSET=GoogleMapsCompatible'
                            '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}'
                            '&FORMAT=image/png',
                        tileProvider: CancellableNetworkTileProvider(),
                        userAgentPackageName:
                            'com.leulit.enagas.helireport_desherbaje',
                        maxNativeZoom: 20,
                      ),
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
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            child: _DragEndpointMarker(
                              kind: EndpointKind.inicio,
                              point: controller.inicio.value,
                              color:
                                  controller.colorFor(EndpointKind.inicio),
                              revertTick: controller.revertTick.value,
                              onDragStart: () =>
                                  controller.isDraggingMarker.value = true,
                              onDragEnd: (p) {
                                controller.isDraggingMarker.value = false;
                                controller.onDragEnd(
                                    EndpointKind.inicio, p);
                              },
                              onDragCancel: () =>
                                  controller.isDraggingMarker.value = false,
                            ),
                          ),
                          Marker(
                            point: controller.fin.value,
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            child: _DragEndpointMarker(
                              kind: EndpointKind.fin,
                              point: controller.fin.value,
                              color:
                                  controller.colorFor(EndpointKind.fin),
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
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: _ZoomControls(mapController: _mapController),
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
                  'Arrastra los puntos A y B sobre el gasoducto',
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
// Zoom controls (mismo estilo que _ZoomControls de segmento_detalle_page).
// ─────────────────────────────────────────────────────────────────────────────

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({required this.mapController});
  final MapController mapController;

  void _zoomIn() {
    final cam = mapController.camera;
    mapController.move(cam.center, (cam.zoom + 1).clamp(5, 20));
  }

  void _zoomOut() {
    final cam = mapController.camera;
    mapController.move(cam.center, (cam.zoom - 1).clamp(5, 20));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(icon: Icons.add, onTap: _zoomIn, isTop: true),
          Container(height: 1, color: Colors.grey.shade200),
          _ZoomButton(icon: Icons.remove, onTap: _zoomOut, isTop: false),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.onTap,
    required this.isTop,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    final radius = isTop
        ? const BorderRadius.vertical(top: Radius.circular(8))
        : const BorderRadius.vertical(bottom: Radius.circular(8));
    return Material(
      color: Colors.white,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.grey.shade800, size: 20),
        ),
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
        widget.onDragStart();
      },
      onPointerMove: (event) {
        if (event.pointer != _activePointer || _startLocal == null) return;
        setState(() =>
            _accumulated = event.localPosition - _startLocal!);
      },
      onPointerUp: (event) {
        if (event.pointer != _activePointer) return;
        _activePointer = -1;
        _startLocal = null;
        final camera = MapCamera.of(context);
        final base = camera.latLngToScreenOffset(widget.point);
        final target = base + _accumulated;
        final newPos = camera.offsetToCrs(target);
        setState(() => _accumulated = Offset.zero);
        widget.onDragEnd(newPos);
      },
      onPointerCancel: (event) {
        if (event.pointer != _activePointer) return;
        _activePointer = -1;
        _startLocal = null;
        setState(() => _accumulated = Offset.zero);
        widget.onDragCancel();
      },
      child: Transform.translate(
        offset: _accumulated,
        child: Container(
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black54, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Center(
            child: Text(
              widget.kind == EndpointKind.inicio ? 'A' : 'B',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
