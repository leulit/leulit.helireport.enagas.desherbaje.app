import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_compass/flutter_map_compass.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:leulit_flutter_fullresponsive/leulit_flutter_fullreponsive.dart';
import '../../core/api_endpoints.dart';
import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../core/services/gasoductos_service.dart';
import '../../core/services/pks_service.dart';
import '../../domain/entities/segmento_entity.dart';
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
          'Mapa',
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
            onPressed: () => Get.offAllNamed(AppRoutes.segmentos),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined,
                color: AppColors.moduleGreen),
            tooltip: 'Forzar envío',
            onPressed: () => Get.toNamed(AppRoutes.forzarEnvio),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.moduleGreen),
            tooltip: 'Salir',
            onPressed: _logout,
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
              // Actividades layer — polylines coloreadas por estado.
              // Envuelta en GestureDetector para permitir tap-to-edit: el
              // hit-test del PolylineLayer solo dispara onTap si el tap cae
              // sobre una línea, por lo que fuera de ellas el gesto pasa al
              // mapa.
              Obx(() {
                // Re-leemos los Rx de filtros para que el Obx se suscriba.
                controller.rxEstado.value;
                controller.rxTipo.value;
                return GestureDetector(
                  onTap: controller.onSegmentoPolylineTap,
                  child: PolylineLayer<SegmentoEntity>(
                    hitNotifier: controller.segmentosHitNotifier,
                    polylines: controller.filteredSegmentos
                        .map((s) => Polyline<SegmentoEntity>(
                              points: s.points,
                              color: s.color,
                              strokeWidth: 5.0,
                              borderColor: Colors.white,
                              borderStrokeWidth: 1.0,
                              hitValue: s.segmento,
                            ))
                        .toList(),
                  ),
                );
              }),
              // Actividades layer — labels en el centroide de cada segmento (zoom > 14)
              Obx(() {
                if (controller.currentZoom.value <= 12) {
                  return const SizedBox.shrink();
                }
                controller.rxEstado.value;
                controller.rxTipo.value;
                return MarkerLayer(
                  markers: controller.filteredSegmentos
                      .map((s) => Marker(
                            point: s.centroid,
                            width: 0.2.w,
                            height: 32,
                            child: _SegmentoLabel(
                              segmentoInfo: s,
                              onTap: () =>
                                  controller.navigateToSegmento(s.segmento),
                            ),
                          ))
                      .toList(),
                );
              }),
              // PKs layer — solo visibles a partir de zoom > 12 para evitar
              // sobrecargar el mapa.
              Obx(() {
                if (controller.currentZoom.value <= 14) {
                  return const SizedBox.shrink();
                }
                return MarkerLayer(
                  markers: controller.pks.map((p) {
                    final w = (p.label.length * 7.0 + 24).clamp(56.0, 140.0);
                    return Marker(
                      point: p.point,
                      width: w,
                      height: 30,
                      alignment: Alignment.bottomCenter,
                      child: _PkMarker(label: p.label),
                    );
                  }).toList(),
                );
              }),
              // Capas de "Líneas de corte" (polylines + drag markers +
              // warning). Internamente filtran por cutStateOn && zoomOk.
              ...buildLinesCutMapLayers(controller.linesCut),
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
          // Filtros (Estado / Tipo) en la parte superior, sobre el mapa.
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: _FiltrosBar(controller: controller),
          ),
          // Botones de zoom (bottom-right, a la izquierda del compass)
          Positioned(
            bottom: 40,
            right: 58,
            child: _ZoomControls(controller: controller),
          ),
          // Botón principal "Líneas de corte" (bottom-left). Cambia a
          // "Aplicar corte" cuando las dos líneas están listas.
          Positioned(
            bottom: 40,
            left: 10,
            child: LinesCutModeButton(
              controller: controller.linesCut,
              onApplyCut: controller.applyLinesCut,
            ),
          ),
          // Panel de control de la feature (arriba-izquierda, bajo filtros).
          Positioned(
            top: 56,
            left: 8,
            right: 8,
            child: LinesCutControlPanel(controller: controller.linesCut),
          ),
          // Status de la carga de PKs (bottom-right, encima del compass)
          const Positioned(
            bottom: 96,
            right: 10,
            child: _PksLoadStatus(),
          ),
          // Banner de error no-bloqueante
          Obx(() {
            final errG = controller.errorGasoductos.value;
            final errA = controller.errorSegmentos.value;
            if (errG == null && errA == null) return const SizedBox.shrink();
            return Positioned(
              top: 64,
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
          // Indicador de carga en la parte inferior con progreso por etapa
          const Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _MapLoadBanner(),
          ),
        ],
      ),
    );
  }
}

/// Marcador estilo pin para un PK: label en una píldora con cola triangular
/// apuntando hacia la coordenada exacta. La punta del triángulo coincide con
/// el geo-point gracias a `Marker.alignment = Alignment.bottomCenter`.
class _PkMarker extends StatelessWidget {
  final String label;
  const _PkMarker({required this.label});

  static const _fill = Color(0xFFFFC107); // amber 500
  static const _border = Color(0xFF263238); // blue grey 900

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _fill,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _border, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
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
          painter: _PkTrianglePainter(fill: _fill, border: _border),
        ),
      ],
    );
  }
}

class _PkTrianglePainter extends CustomPainter {
  final Color fill;
  final Color border;
  const _PkTrianglePainter({required this.fill, required this.border});

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
  bool shouldRepaint(covariant _PkTrianglePainter old) =>
      old.fill != fill || old.border != border;
}

// ─── Barra de filtros (Estado / Tipo) ────────────────────────────────────────

const Map<EstadoActividad, Color> _estadoFilterColors = {
  EstadoActividad.propuesta: Color(0xFF78909C),
  EstadoActividad.validada: Color(0xFF1976D2),
  EstadoActividad.contratista: Color.fromARGB(255, 241, 70, 219),
  EstadoActividad.ejecucion: Color(0xFFF57C00),
  EstadoActividad.finalizada: Color(0xFF388E3C),
  EstadoActividad.cerrada: Color(0xFF546E7A),
};

const Map<TipoActividad, Color> _tipoFilterColors = {
  TipoActividad.desbroceManual: Color(0xFF6D4C41),
  TipoActividad.desbroceMecanico: Color(0xFFBF360C),
  TipoActividad.deshierbePosiciones: Color(0xFF0277BD),
  TipoActividad.desherbajeSelectivo: Color(0xFF00796B),
  TipoActividad.desratizacion: Color(0xFF6A1B9A),
  TipoActividad.resiembre: Color(0xFF558B2F),
  TipoActividad.talaArboles: Color(0xFF4E342E),
};

class _FiltrosBar extends StatelessWidget {
  final MapaGlobalController controller;
  const _FiltrosBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _FilterDropdown<EstadoActividad>(
              icon: Icons.flag_outlined,
              label: '',
              groupColor: const Color(0xFF455A64),
              rxValue: controller.rxEstado,
              items: const [
                EstadoActividad.propuesta,
                EstadoActividad.validada,
                EstadoActividad.ejecucion,
                EstadoActividad.finalizada,
              ],
              itemLabel: (e) => e.etiqueta,
              itemColor: (e) =>
                  _estadoFilterColors[e] ?? const Color(0xFF455A64),
              onChanged: controller.setEstado,
            ),
            _FilterDropdown<TipoActividad>(
              icon: Icons.construction_outlined,
              label: '',
              groupColor: const Color(0xFF2E7D32),
              rxValue: controller.rxTipo,
              items: TipoActividad.values,
              itemLabel: (t) => t.etiqueta,
              itemColor: (t) =>
                  _tipoFilterColors[t] ?? const Color(0xFF2E7D32),
              onChanged: controller.setTipo,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color groupColor;
  final Rx<T?> rxValue;
  final List<T> items;
  final String Function(T) itemLabel;
  final Color Function(T) itemColor;
  final void Function(T?) onChanged;

  const _FilterDropdown({
    required this.icon,
    required this.label,
    required this.groupColor,
    required this.rxValue,
    required this.items,
    required this.itemLabel,
    required this.itemColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: groupColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: groupColor.withValues(alpha: 0.25), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: groupColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: groupColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 4),
          Obx(() {
            final selected = rxValue.value;
            final selectedColor =
                selected != null ? itemColor(selected) : groupColor;
            return DropdownButton<T?>(
              value: selected,
              isDense: true,
              underline: const SizedBox.shrink(),
              icon:
                  Icon(Icons.arrow_drop_down, size: 16, color: selectedColor),
              style: TextStyle(
                fontSize: 12,
                color: selectedColor,
                fontWeight: FontWeight.w600,
              ),
              selectedItemBuilder: (_) => [
                Text(
                  'Todos',
                  style: TextStyle(
                    fontSize: 12,
                    color: groupColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ...items.map((e) => Text(
                      itemLabel(e),
                      style: TextStyle(
                        fontSize: 12,
                        color: itemColor(e),
                        fontWeight: FontWeight.w600,
                      ),
                    )),
              ],
              items: [
                DropdownMenuItem<T?>(
                  value: null,
                  child: Text(
                    'Todos',
                    style: TextStyle(fontSize: 12, color: groupColor),
                  ),
                ),
                ...items.map((e) => DropdownMenuItem<T?>(
                      value: e,
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: itemColor(e),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            itemLabel(e),
                            style: TextStyle(
                              fontSize: 12,
                              color: itemColor(e),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
              onChanged: onChanged,
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

/// Indicador de progreso del pipeline de descarga de PKs. Se muestra solo
/// mientras `PksService.isLoading` es true y, si hay total conocido, pinta
/// el contador `procesados/total` de ficheros JSON.
class _PksLoadStatus extends StatelessWidget {
  const _PksLoadStatus();

  @override
  Widget build(BuildContext context) {
    final pksService = Get.find<PksService>();
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

/// Banner inferior con el progreso global de carga del mapa. Lee de forma
/// reactiva los contadores de `GasoductosService` y `PksService`, y el flag
/// `isLoadingSegmentos` del controlador. Muestra la etapa activa (etiqueta +
/// contador `X/Y`) y una barra de progreso determinista cuando el total es
/// conocido; si no, cae a un indicador indeterminado.
class _MapLoadBanner extends StatelessWidget {
  const _MapLoadBanner();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MapaGlobalController>();
    final gasoductos = Get.find<GasoductosService>();
    final pks = Get.find<PksService>();

    return Obx(() {
      final isGas = controller.isLoadingGasoductos.value;
      final isPks = controller.isLoadingPks.value;
      final isSeg = controller.isLoadingSegmentos.value;
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
