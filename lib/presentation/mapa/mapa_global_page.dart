import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_compass/flutter_map_compass.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:leulit_flutter_fullresponsive/leulit_flutter_fullreponsive.dart';
import '../../core/api_endpoints.dart';
import '../../core/app_theme.dart';
import 'mapa_global_controller.dart';

class MapaGlobalPage extends GetView<MapaGlobalController> {
  const MapaGlobalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.moduleGreenLight,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 2, color: const Color(0xFFA5D6A7)),
        ),
        leading: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.eco, color: AppColors.moduleGreen),
        ),
        title: const Text(
          'Mapa de Actividades',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.moduleGreenText,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt, color: AppColors.moduleGreen),
            tooltip: 'Ver listado',
            onPressed: Get.back,
          ),
          Obx(() {
            if (controller.isLoading) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.moduleGreen,
                  ),
                ),
              );
            }
            return IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.moduleGreen),
              onPressed: controller.reloadSegmentos,
            );
          }),
          _LeyendaButton(),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: controller.mapController,
            options: MapOptions(
              initialCenter: const LatLng(40.4168, -3.7038),
              initialZoom: 7,
              minZoom: 5,
              maxZoom: 20,
              onMapEvent: controller.onMapEvent,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              // Capa base PNOA IGN
              TileLayer(
                urlTemplate: ApiEndpoints.pnoaWmts,
                tileProvider: CancellableNetworkTileProvider(),
                userAgentPackageName:
                    'com.leulit.enagas.helireport_desherbaje',
                additionalOptions: const {
                  'User-Agent': 'helireport-desherbaje',
                },
              ),
              // Gasoductos layer
              Obx(() => PolylineLayer(
                    polylines: controller.gasoductosPolylines.toList(),
                  )),
              // Actividades layer — polylines coloreadas por estado
              Obx(() => PolylineLayer(
                    polylines: controller.segmentos
                        .map((s) => Polyline(
                              points: s.points,
                              color: s.color,
                              strokeWidth: 5.0,
                              borderColor: Colors.white,
                              borderStrokeWidth: 1.0,
                            ))
                        .toList(),
                  )),
              // Actividades layer — labels en el centroide de cada segmento (zoom > 14)
              Obx(() {
                if (controller.currentZoom.value <= 12) {
                  return const SizedBox.shrink();
                }
                return MarkerLayer(
                  markers: controller.segmentos
                      .map((s) => Marker(
                            point: s.centroid,
                            width: 0.2.w,
                            height: 32,
                            child: _SegmentoLabel(
                              segmentoInfo: s,
                              onTap: () => controller.navigateToSegmento(s.segmento),
                            ),
                          ))
                      .toList(),
                );
              }),
              // Brújula estilo cupertino (bottom-right, encima del indicador de zoom)
              const MapCompass.cupertino(
                rotationDuration: Duration(milliseconds: 300),
                hideIfRotatedNorth: false,
                alignment: Alignment.bottomRight,
                padding: EdgeInsets.only(bottom: 48, right: 10),
              ),
              // Indicador de zoom (bottom-right, esquina inferior)
              const _ZoomDisplay(),
            ],
          ),
          // Botones de zoom (bottom-right, a la izquierda del compass)
          Positioned(
            bottom: 40,
            right: 58,
            child: _ZoomControls(controller: controller),
          ),
          // Banner de error no-bloqueante
          Obx(() {
            final errG = controller.errorGasoductos.value;
            final errA = controller.errorSegmentos.value;
            if (errG == null && errA == null) return const SizedBox.shrink();
            return Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Material(
                borderRadius: BorderRadius.circular(8),
                elevation: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber,
                          color: Colors.orange.shade700, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [if (errG != null) errG, if (errA != null) errA]
                              .join(' · '),
                          style: TextStyle(
                              fontSize: 12, color: Colors.orange.shade800),
                        ),
                      ),
                      TextButton(
                        onPressed: controller.loadAll,
                        style: TextButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Reintentar',
                            style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          // Indicador de carga sutil en la parte inferior
          Obx(() {
            if (!controller.isLoading) return const SizedBox.shrink();
            return const Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Material(
                borderRadius: BorderRadius.all(Radius.circular(8)),
                elevation: 3,
                child: Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.moduleGreen,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text('Cargando datos del mapa...',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Botones + / - para controlar el zoom del mapa.
class _ZoomControls extends StatelessWidget {
  final MapaGlobalController controller;

  const _ZoomControls({required this.controller});

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
          _ZoomButton(
            icon: Icons.add,
            onTap: controller.zoomIn,
            isTop: true,
          ),
          Container(height: 1, color: Colors.grey.shade200),
          _ZoomButton(
            icon: Icons.remove,
            onTap: controller.zoomOut,
            isTop: false,
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isTop;

  const _ZoomButton({
    required this.icon,
    required this.onTap,
    required this.isTop,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.vertical(
        top: isTop ? const Radius.circular(8) : Radius.zero,
        bottom: isTop ? Radius.zero : const Radius.circular(8),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.vertical(
          top: isTop ? const Radius.circular(8) : Radius.zero,
          bottom: isTop ? Radius.zero : const Radius.circular(8),
        ),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: AppColors.moduleGreen),
        ),
      ),
    );
  }
}

/// Label clickeable sobre el centroide de cada segmento de actividad.
class _SegmentoLabel extends StatelessWidget {
  final SegmentoMapInfo segmentoInfo;
  final VoidCallback onTap;

  const _SegmentoLabel({required this.segmentoInfo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = segmentoInfo.color;
    final longKm = segmentoInfo.segmento.longitudKm;
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
            BoxShadow(
                color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
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

/// Indicador del nivel de zoom actual. Usa MapCamera.of(context) para
/// actualizarse automáticamente con cada movimiento del mapa.
class _ZoomDisplay extends StatelessWidget {
  const _ZoomDisplay();

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8, right: 10),
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            'Zoom: ${camera.zoom.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón de leyenda en la AppBar.
class _LeyendaButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.info_outline, color: AppColors.moduleGreen),
      onPressed: () => _showLeyenda(context),
    );
  }

  void _showLeyenda(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Leyenda',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const _LeyendaItem(
                color: Color(0xFF1565C0), label: 'Gasoductos (CTs)'),
            const _LeyendaItem(
                color: AppColors.estadoPropuesta, label: 'Propuesta'),
            const _LeyendaItem(
                color: AppColors.estadoEjecucion, label: 'En Ejecución'),
            const SizedBox(height: 8),
            const Text(
              'Pulsa sobre un label para abrir la actividad',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _LeyendaItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LeyendaItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
