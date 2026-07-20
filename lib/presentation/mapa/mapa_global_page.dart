import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_compass/flutter_map_compass.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_endpoints.dart';
import '../../core/app_di.dart';
import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/filtros_segmentos_bar.dart';
import '../../core/widgets/my_current_location_layer.dart';
import '../../domain/entities/segmento_entity.dart';
import 'layers/gasoductos_map_layer.dart';
import 'layers/pks_map_layer.dart';
import 'layers/hitos_map_layer.dart';
import 'layers/posiciones_fijas_map_layer.dart';
import 'layers/segmentos_map_controller.dart';
import 'layers/segmentos_map_layer.dart';
import 'lines_cut/lines_cut_ui.dart';
import 'mapa_global_controller.dart';

class MapaGlobalPage extends GetView<MapaGlobalController> {
  const MapaGlobalPage({super.key});

  void _logout() {
    Get.dialog(
      AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que quieres cerrar sesión?'),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              Get.back();
              Get.offAllNamed(AppRoutes.login);
            },
            child: const Text('Salir', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // NF-8: PopScope ensures the final GPS flush completes (awaited) before
    // the route is popped. onClose() keeps unawaited(stop()) as safety net.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) await controller.stopTracking();
      },
      child: Scaffold(
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
          actions: [
            IconButton(
              icon: const Icon(Icons.list_alt, color: AppColors.moduleGreen),
              tooltip: 'Ver listado',
              onPressed: () => Get.offAllNamed(AppRoutes.segmentos),
            ),
            IconButton(
              icon: const Icon(Icons.cloud_upload_outlined,
                  color: AppColors.moduleGreen),
              tooltip: 'Forzar envío',
              onPressed: () => Get.toNamed(AppRoutes.forzarEnvio),
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
                onPressed: controller.reloadAll,
              );
            }),
            _LeyendaButton(),
            IconButton(
              icon: const Icon(Icons.logout, color: AppColors.moduleGreen),
              tooltip: 'Salir',
              onPressed: _logout,
            ),
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
                onMapReady: controller.onMapReady,
                onMapEvent: controller.onMapEvent,
                onTap: controller.onMapTap,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: ApiEndpoints.pnoaWmts,
                  tileProvider: CancellableNetworkTileProvider(),
                  userAgentPackageName:
                      'com.leulit.enagas.helireport_desherbaje',
                  additionalOptions: const {
                    'User-Agent': 'helireport-desherbaje',
                  },
                ),
                const GasoductosMapLayer(),
                SegmentosMapLayer(currentZoom: controller.currentZoom),
                const PksMapLayer(),
                const HitosMapLayer(),
                const PosicionesFijasMapLayer(),
                ValueListenableBuilder<bool>(
                  valueListenable: controller.followHeading,
                  builder: (_, follow, __) => MyCurrentLocationLayer(
                    alignDirectionOnUpdate:
                        follow ? AlignOnUpdate.always : AlignOnUpdate.never,
                    // once: centra en el primer fix GPS al abrir el mapa;
                    // después el usuario puede panear libre (always lo
                    // bloquearía).
                    alignPositionOnUpdate: AlignOnUpdate.once,
                    alignPositionStream: controller.alignPositionStream,
                  ),
                ),
                ...buildLinesCutMapLayers(controller.linesCut),
                ValueListenableBuilder<bool>(
                  valueListenable: controller.followHeading,
                  builder: (_, follow, __) => MapCompass(
                    // -45: el icono cupertino ya viene rotado en el asset.
                    rotationOffset: -45,
                    icon: _CompassIcon(followHeading: follow),
                    rotationDuration: const Duration(milliseconds: 300),
                    hideIfRotatedNorth: false,
                    alignment: Alignment.bottomRight,
                    // Caja del IconButton interno = 50 (el icono supera el
                    // mínimo táctil de 48). bottom 43 alinea su centro con el
                    // del botón "mi ubicación" (48 + 40/2 = 68); right 5 deja
                    // ~8px entre ambos círculos visibles.
                    padding: const EdgeInsets.only(bottom: 43, right: 5),
                    onPressed: controller.toggleFollowHeading,
                  ),
                ),
                const _ZoomDisplay(),
              ],
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: _FiltrosBar(),
            ),
            Positioned(
              bottom: 40,
              left: 10,
              child: LinesCutModeButton(
                controller: controller.linesCut,
                onApplyCut: controller.applyLinesCut,
              ),
            ),
            Positioned(
              top: 56,
              left: 8,
              right: 8,
              child: LinesCutControlPanel(controller: controller.linesCut),
            ),
            const Positioned(
              bottom: 96,
              right: 10,
              child: _PksLoadStatus(),
            ),
            Positioned(
              bottom: 48,
              right: 58,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 3,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: controller.centerOnMyLocation,
                  child: const Padding(
                    padding: EdgeInsets.all(9),
                    child: Icon(Icons.my_location,
                        size: 22, color: AppColors.moduleGreen),
                  ),
                ),
              ),
            ),
            const Positioned(
              top: 64,
              left: 16,
              right: 16,
              child: _ErrorBanner(),
            ),
            const Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _MapLoadBanner(),
            ),
          ],
        ),
      ), // end Scaffold
    ); // end PopScope
  }
}

// ─── Barra de filtros ─────────────────────────────────────────────────────────

/// Icono de la brújula del mapa. Réplica del look `MapCompass.cupertino`, con
/// la aguja en rojo cuando el mapa sigue el rumbo del dispositivo y en gris
/// cuando está fijo al norte.
class _CompassIcon extends StatelessWidget {
  final bool followHeading;

  const _CompassIcon({required this.followHeading});

  /// Tamaño del glifo. El dibujo ocupa ~0.8 de su caja, así que 50 rinde un
  /// círculo visible de ~40 — el diámetro del botón "mi ubicación"
  /// (padding 9 + icono 22).
  static const double _size = 50;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(
          CupertinoIcons.compass,
          color: followHeading ? Colors.red : Colors.blueGrey,
          size: _size,
        ),
        const Icon(
          CupertinoIcons.compass_fill,
          color: Colors.white54,
          size: _size,
        ),
        const Icon(CupertinoIcons.circle, color: Colors.black, size: _size),
      ],
    );
  }
}

class _FiltrosBar extends GetView<SegmentosMapController> {
  const _FiltrosBar();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controller.filtrosVisible,
      builder: (context, visible, _) {
        if (!visible) return const SizedBox.shrink();
        // `SegmentoFiltrosRow` ya trae su propio Material sin elevación; se
        // envuelve aquí en uno con elevation:2 para conservar la sombra que
        // tenía la barra flotante sobre el mapa, sin duplicar bordes.
        return Material(
          borderRadius: BorderRadius.circular(14),
          elevation: 2,
          child: Obx(() => SegmentoFiltrosRow(
                rxEstado: controller.rxEstado,
                estadoItems: const [
                  EstadoActividad.propuesta,
                  EstadoActividad.contratista,
                  EstadoActividad.validada,
                  EstadoActividad.ejecucion,
                  EstadoActividad.finalizada,
                ],
                onEstado: controller.setEstado,
                rxTipo: controller.rxTipo,
                onTipo: controller.setTipo,
                rxCt: controller.rxCt,
                ctItems: controller.ctsDisponibles,
                ctLabel: controller.ctLabel,
                onCt: controller.setCt,
              )),
        );
      },
    );
  }
}

// ─── Zoom display ─────────────────────────────────────────────────────────────

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

// ─── Leyenda ─────────────────────────────────────────────────────────────────

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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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

// ─── Banners de estado ────────────────────────────────────────────────────────

class _PksLoadStatus extends StatelessWidget {
  const _PksLoadStatus();

  @override
  Widget build(BuildContext context) {
    final pksService = AppDI.pksService;
    return Obx(() {
      if (!pksService.isLoading.value) return const SizedBox.shrink();
      final total = pksService.totalFiles.value;
      final done = pksService.processedFiles.value;
      final label = total == 0 ? 'Cargando PKs…' : 'PKs $done/$total';
      return Material(
        borderRadius: BorderRadius.circular(8),
        elevation: 3,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.moduleGreen,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner();

  @override
  Widget build(BuildContext context) {
    final mapCtrl = Get.find<MapaGlobalController>();
    final segCtrl = Get.find<SegmentosMapController>();
    return Obx(() {
      final errG = mapCtrl.errorGasoductos.value;
      final errA = segCtrl.error.value;
      if (errG == null && errA == null) return const SizedBox.shrink();
      return Material(
        borderRadius: BorderRadius.circular(8),
        elevation: 2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  [if (errG != null) errG, if (errA != null) errA].join(' · '),
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                ),
              ),
              TextButton(
                onPressed: mapCtrl.loadAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Reintentar', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _MapLoadBanner extends StatelessWidget {
  const _MapLoadBanner();

  @override
  Widget build(BuildContext context) {
    final mapCtrl = Get.find<MapaGlobalController>();
    final segCtrl = Get.find<SegmentosMapController>();
    final gasoductos = AppDI.gasoductosService;
    final pks = AppDI.pksService;

    return Obx(() {
      final isGas = mapCtrl.isLoadingGasoductos.value;
      final isPks = mapCtrl.isLoadingPks.value;
      final isSeg = segCtrl.isLoading.value;
      if (!isGas && !isPks && !isSeg) return const SizedBox.shrink();

      final String stageLabel;
      final int total;
      final int done;
      if (isGas) {
        stageLabel = 'Cargando gasoductos';
        total = gasoductos.totalFiles.value;
        done = gasoductos.processedFiles.value;
      } else if (isPks) {
        stageLabel = 'Cargando PKs';
        total = pks.totalFiles.value;
        done = pks.processedFiles.value;
      } else {
        stageLabel = 'Cargando actividades';
        total = 0;
        done = 0;
      }

      final hasDeterminate = total > 0;
      final progress = hasDeterminate ? (done / total).clamp(0.0, 1.0) : null;
      final counter = hasDeterminate ? ' · $done/$total' : '';

      return Material(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.moduleGreen,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$stageLabel$counter',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(3)),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.moduleGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
