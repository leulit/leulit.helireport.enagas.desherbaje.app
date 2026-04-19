import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_compass/flutter_map_compass.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:leulit_flutter_fullresponsive/leulit_flutter_fullreponsive.dart';
import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../core/extensions.dart';
import '../../core/services/gasoductos_service.dart';
import '../../domain/entities/actividad_entity.dart';
import '../../domain/entities/segmento_entity.dart';
import 'actividad_detalle_controller.dart';

class ActividadDetallePage extends GetView<ActividadDetalleController> {
  const ActividadDetallePage({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ActividadDetalleController>(
      builder: (_) {
        final actividad = controller.actividad;
        final accent = AppColors.accentForEstado(actividad.estado);
        return Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFFA5D6A7),
            foregroundColor: Colors.white,
            title: Text(
              '#${actividad.id}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.list_alt),
                tooltip: 'Ver listado',
                onPressed: () => Get.until(
                    (route) => route.settings.name == AppRoutes.segmentos),
              ),
              IconButton(
                icon: const Icon(Icons.map_outlined),
                tooltip: 'Ver mapa',
                onPressed: () => Get.toNamed(AppRoutes.mapa),
              ),
              PopupMenuButton<EstadoActividad>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: controller.cambiarEstado,
                itemBuilder: (_) => EstadoActividad.values
                    .map((e) => PopupMenuItem(
                          value: e,
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: AppColors.accentForEstado(e),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(e.etiqueta),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
          body: Column(
            children: [
              Flexible(
                flex: 2,
                child: _PanelSegmentos(
                  actividad: actividad,
                  accentColor: accent,
                  onFotosSegmento: controller.irAFotosConSegmento,
                ),
              ),
              Container(height: 2, color: accent.withValues(alpha: 0.4)),
              Flexible(
                flex: 3,
                child: _MapaDetalle(
                  actividad: actividad,
                  accentColor: accent,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PanelSegmentos extends StatelessWidget {
  final ActividadEntity actividad;
  final Color accentColor;
  final void Function(SegmentoEntity segmento) onFotosSegmento;

  const _PanelSegmentos({
    required this.actividad,
    required this.accentColor,
    required this.onFotosSegmento,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: AppColors.bgForEstado(actividad.estado),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Text(
                  "Descripción: ${actividad.descripcion}",
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _MetricBadge(
                    icon: Icons.straighten,
                    label: '${actividad.longitudTotal.toStringAsFixed(0)} m',
                  ),
                  const SizedBox(width: 8),
                  _MetricBadge(
                    icon: Icons.square_foot,
                    label: '${actividad.superficieM2.toStringAsFixed(0)} m²',
                  ),
                  const SizedBox(width: 8),
                  _MetricBadge(
                    icon: Icons.event,
                    label: dateFormat.format(actividad.fechaInicio),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Row(
            children: [
              Icon(Icons.route_outlined, size: 14, color: accentColor),
              const SizedBox(width: 4),
              Text(
                '${actividad.segmentos.length} segmentos',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accentColor.getContrastTextColor(),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: actividad.segmentos.isEmpty
              ? const Center(
                  child: Text('Sin segmentos',
                      style: TextStyle(color: Colors.grey)))
              : ListView.separated(
                  itemCount: actividad.segmentos.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _SegmentoTile(
                    segmento: actividad.segmentos[i],
                    index: i,
                    accentColor: accentColor,
                    superficieM2: actividad.superficieM2,
                    onFotos: () => onFotosSegmento(actividad.segmentos[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _MetricBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetricBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.blueGrey.shade400),
        const SizedBox(width: 3),
        Text(label,
            style:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _SegmentoTile extends StatelessWidget {
  final SegmentoEntity segmento;
  final int index;
  final Color accentColor;
  final double superficieM2;
  final VoidCallback onFotos;

  const _SegmentoTile({
    required this.segmento,
    required this.index,
    required this.accentColor,
    required this.superficieM2,
    required this.onFotos,
  });

  @override
  Widget build(BuildContext context) {
    final estadoColor = AppColors.accentForEstado(segmento.estado);
    final estadoTextColor = AppColors.textOnAccentForEstado(segmento.estado);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: accentColor.withValues(alpha: 0.15),
        child: Text(
          '${index + 1}',
          style: TextStyle(
            color: accentColor.getContrastTextColor(),
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
      title: Text(
        segmento.descripcion!,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        children: [
          Row(
            children: [
              _Metric(
                icon: Icons.straighten,
                value: '${segmento.longitudKm.toStringAsFixed(2)} km',
                label: 'Longitud',
              ),
              const SizedBox(width: 16),
              _Metric(
                icon: Icons.square_foot,
                value: '${segmento.superficie.toStringAsFixed(0)} m²',
                label: 'Superficie',
              ),              
            ]
          ),
          SizedBox(height: 0.01.h),
          Row(
            children: [
              _Chip(
                icon: Icons.eco_outlined,
                label: segmento.tipoActividad.etiqueta,
                color: const Color(0xFF388E3C),
              ),
              SizedBox(width: 0.02.w),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: estadoColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  segmento.estado.etiqueta,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: estadoTextColor,
                  ),
                ),
              ),
            ]
          ),
        ]
      ),
      trailing: IconButton(
        icon: Icon(Icons.camera_alt, size: 18, color: accentColor),
        tooltip: 'Fotos',
        onPressed: onFotos,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }
}

class _MapaDetalle extends StatefulWidget {
  final ActividadEntity actividad;
  final Color accentColor;

  const _MapaDetalle({
    required this.actividad,
    required this.accentColor,
  });

  @override
  State<_MapaDetalle> createState() => _MapaDetalleState();
}

class _MapaDetalleState extends State<_MapaDetalle> {
  final _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final allPoints = widget.actividad.segmentos
        .expand((s) => s.ubicacionGis)
        .toList();

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: allPoints.isNotEmpty
            ? allPoints[allPoints.length ~/ 2]
            : const LatLng(40.4168, -3.7038),
        initialZoom: 14,
        onMapReady: () {
          if (allPoints.isNotEmpty) {
            final bounds = LatLngBounds.fromPoints(allPoints);
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.all(50),
              ),
            );
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://www.ign.es/wmts/pnoa-ma?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
              '&LAYER=OI.OrthoimageCoverage&STYLE=default'
              '&TILEMATRIXSET=GoogleMapsCompatible'
              '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png',
          tileProvider: CancellableNetworkTileProvider(),
          userAgentPackageName: 'com.leulit.enagas.helireport_desherbaje',
          additionalOptions: const {'User-Agent': 'helireport-desherbaje'},
        ),
        Obx(() {
          final gasoductos = Get.find<GasoductosService>().polylines;
          return PolylineLayer(
            polylines: gasoductos
                .map((p) => Polyline(
                      points: p.points,
                      color: p.color.withValues(alpha: 0.6),
                      strokeWidth: p.strokeWidth * 0.8,
                    ))
                .toList(),
          );
        }),
        PolylineLayer(
          polylines: widget.actividad.segmentos
              .map((s) => Polyline(
                    points: s.ubicacionGis,
                    color: widget.accentColor,
                    strokeWidth: 5.0,
                    borderColor: Colors.white,
                    borderStrokeWidth: 1.5,
                  ))
              .toList(),
        ),
        MarkerLayer(
          markers: widget.actividad.segmentos
              .asMap()
              .entries
              .where((e) => e.value.ubicacionGis.isNotEmpty)
              .map((entry) => Marker(
                    point: entry.value.ubicacionGis.first,
                    width: 26,
                    height: 26,
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.accentColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          '${entry.key + 1}',
                          style: TextStyle(
                            color: widget.accentColor.getContrastTextColor(),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const MapCompass.cupertino(
          rotationDuration: Duration(milliseconds: 300),
          hideIfRotatedNorth: false,
          alignment: Alignment.bottomRight,
          padding: EdgeInsets.only(bottom: 48, right: 10),
        ),
        const _ZoomIndicator(),
      ],
    );
  }
}

class _ZoomIndicator extends StatelessWidget {
  const _ZoomIndicator();

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
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}


class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}


class _Metric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _Metric(
      {required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 11, color: Colors.blueGrey.shade400),
            const SizedBox(width: 3),
            Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF37474F),
              ),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(fontSize: 9, color: Colors.blueGrey.shade400),
        ),
      ],
    );
  }
}
