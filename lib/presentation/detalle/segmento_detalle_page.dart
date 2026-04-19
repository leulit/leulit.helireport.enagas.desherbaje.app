import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/api_endpoints.dart';
import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../core/extensions.dart';
import '../../data/model/mensaje_entity.dart';
import '../../domain/entities/imagen_segmento_entity.dart';
import '../../domain/entities/segmento_entity.dart';
import 'segmento_detalle_controller.dart';

class SegmentoDetallePage extends GetView<SegmentoDetalleController> {
  const SegmentoDetallePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: _buildAppBar(),
        body: Column(
          children: [
            Expanded(child: _PanelDatosTabs(controller: controller)),
            const Divider(height: 1, color: Color(0xFFA5D6A7)),
            Expanded(child: _MapaSegmento(controller: controller)),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.moduleGreenLight,
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 2, color: const Color(0xFFA5D6A7)),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.moduleGreen),
        tooltip: 'Volver al listado',
        onPressed: () => Get.offAllNamed(AppRoutes.segmentos),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            controller.segmento.id != null
                ? 'Segmento #${controller.segmento.id}'
                : 'Segmento',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.moduleGreenText,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // Reactivo: cuando `user.value` se rellena tras `getCurrentUser()`,
          // este Text se reconstruye automáticamente con el nombre legible.
          Obx(() => Text(
                controller.ctName,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.list_alt, color: AppColors.moduleGreen),
          tooltip: 'Listado de segmentos',
          onPressed: () => Get.offAllNamed(AppRoutes.segmentos),
        ),
        IconButton(
          icon: const Icon(Icons.map_outlined, color: AppColors.moduleGreen),
          tooltip: 'Mapa global',
          onPressed: () => Get.offAllNamed(AppRoutes.mapa),
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: AppColors.moduleGreen),
          tooltip: 'Salir',
          onPressed: _logout,
        ),
      ],
    );
  }

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
}

// ─── Panel superior: tabs Datos / Mensajes / Imágenes ───────────────────────

class _PanelDatosTabs extends StatelessWidget {
  final SegmentoDetalleController controller;
  const _PanelDatosTabs({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppColors.moduleGreenLight,
          child: const TabBar(
            isScrollable: true,
            labelColor: AppColors.moduleGreenText,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.moduleGreen,
            tabs: [
              Tab(icon: Icon(Icons.info_outline), text: 'Datos'),
              Tab(icon: Icon(Icons.forum_outlined), text: 'Mensajes'),
              Tab(icon: Icon(Icons.photo_library_outlined), text: 'Antes'),
              Tab(icon: Icon(Icons.photo_library_outlined), text: 'Después'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              _DatosTab(controller: controller),
              _MensajesTab(mensajes: controller.segmento.mensajes),
              _ImagenesCarousel(
                segmento: controller.segmento,
                tipo: TipoFoto.antes,
              ),
              _ImagenesCarousel(
                segmento: controller.segmento,
                tipo: TipoFoto.despues,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Tab Datos ──────────────────────────────────────────────────────────────

class _DatosTab extends StatelessWidget {
  final SegmentoDetalleController controller;
  const _DatosTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    final s = controller.segmento;
    final longitudKm = s.longitudKm;
    final lengthText = longitudKm >= 1
        ? '${longitudKm.toStringWithComma(decimals: 2)} km'
        : '${s.longitud.toStringAsFixed(0)} m';
    final superficieText = '${s.superficie.toStringWithComma(decimals: 0)} m²';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFA5D6A7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  icon: Icons.timeline,
                  label: 'Traza',
                  value: (s.traza ?? '').isNotEmpty ? s.traza! : '—',
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.straighten,
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    const Text('Long: ',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(lengthText, style: const TextStyle(fontSize: 13)),
                    const Text('  -  ',
                        style: TextStyle(fontSize: 13, color: Colors.grey)),
                    Icon(Icons.square_foot,
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    const Text('Sup: ',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    Flexible(
                      child: Text(
                        superficieText,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _DropdownInlineField<TipoActividad>(
            label: 'Tipo actividad',
            icon: Icons.category_outlined,
            rx: controller.tipoActividad,
            values: TipoActividad.values,
            labelOf: (t) => t.etiqueta,
          ),
          const SizedBox(height: 12),
          _DropdownInlineField<EstadoActividad>(
            label: 'Estado',
            icon: Icons.flag_outlined,
            rx: controller.estado,
            values: EstadoActividad.values,
            labelOf: (e) => e.etiqueta,
          ),
          const SizedBox(height: 16),
          Text(
            'Descripción',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: controller.descripcion.value,
            onChanged: (v) => controller.descripcion.value = v,
            maxLines: 5,
            decoration: InputDecoration(
              hintText:
                  'Describe el área de trabajo o las características del tramo...',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
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

class _DropdownInlineField<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final Rx<T> rx;
  final List<T> values;
  final String Function(T) labelOf;

  const _DropdownInlineField({
    required this.label,
    required this.icon,
    required this.rx,
    required this.values,
    required this.labelOf,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Obx(() => DropdownButtonFormField<T>(
                initialValue: rx.value,
                isDense: true,
                decoration: InputDecoration(
                  prefixIcon:
                      Icon(icon, color: AppColors.moduleGreen, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                items: values
                    .map((v) => DropdownMenuItem<T>(
                          value: v,
                          child: Text(labelOf(v),
                              style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) rx.value = v;
                },
              )),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text('$label: ',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─── Tab Mensajes ───────────────────────────────────────────────────────────

class _MensajesTab extends StatelessWidget {
  final List<MensajeEntity> mensajes;
  const _MensajesTab({required this.mensajes});

  @override
  Widget build(BuildContext context) {
    if (mensajes.isEmpty) {
      return const _EmptyState(
        icon: Icons.forum_outlined,
        message: 'Sin mensajes para este segmento',
      );
    }
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: mensajes.length,
      itemBuilder: (_, i) {
        final m = mensajes[i];
        final author =
            (m.senderUserName != null && m.senderUserName!.isNotEmpty)
                ? m.senderUserName!
                : 'Operador #${m.senderUserId ?? 0}';
        final when = m.sentAt != null ? fmt.format(m.sentAt!) : '';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.moduleGreen,
                    child: const Icon(Icons.person,
                        color: Colors.white, size: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      author,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    when,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(m.mensaje, style: const TextStyle(fontSize: 13)),
            ],
          ),
        );
      },
    );
  }
}

// ─── Tab Imágenes ───────────────────────────────────────────────────────────

/// Carrusel + botón de captura de fotos para un único [TipoFoto] (antes /
/// después). Usa [PageView] con un indicador de puntos.
class _ImagenesCarousel extends StatefulWidget {
  final SegmentoEntity segmento;
  final TipoFoto tipo;

  const _ImagenesCarousel({
    required this.segmento,
    required this.tipo,
  });

  @override
  State<_ImagenesCarousel> createState() => _ImagenesCarouselState();
}

class _ImagenesCarouselState extends State<_ImagenesCarousel> {
  late final PageController _pageController = PageController();
  int _current = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imagenes = widget.segmento.imagenes
        .where((i) => i.tipoFoto == widget.tipo)
        .toList();

    return Column(
      children: [
        Expanded(
          child: imagenes.isEmpty
              ? _EmptyState(
                  icon: Icons.photo_library_outlined,
                  message:
                      'Sin imágenes ${widget.tipo == TipoFoto.antes ? 'antes' : 'después'}',
                )
              : Stack(
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: imagenes.length,
                      onPageChanged: (i) => setState(() => _current = i),
                      itemBuilder: (_, i) => _CarouselSlide(imagen: imagenes[i]),
                    ),
                    if (imagenes.length > 1)
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: _DotsIndicator(
                          count: imagenes.length,
                          current: _current,
                        ),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Get.toNamed(
                AppRoutes.fotos,
                arguments: {
                  'segmento': widget.segmento,
                  'tipo': widget.tipo,
                },
              ),
              icon: const Icon(Icons.add_a_photo),
              label: Text(
                widget.tipo == TipoFoto.antes
                    ? 'Capturar foto antes'
                    : 'Capturar foto después',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CarouselSlide extends StatelessWidget {
  final ImagenSegmentoEntity imagen;
  const _CarouselSlide({required this.imagen});

  @override
  Widget build(BuildContext context) {
    final url = imagen.url;
    if (url == null || url.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        child: const Center(
          child: Icon(Icons.image_not_supported, color: Colors.grey, size: 48),
        ),
      );
    }
    final fullUrl =
        url.startsWith('http') ? url : '${ApiEndpoints.baseUrl}$url';
    return Container(
      color: Colors.black,
      child: CachedNetworkImage(
        imageUrl: fullUrl,
        fit: BoxFit.contain,
        placeholder: (_, __) =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorWidget: (_, __, ___) =>
            const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
      ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  final int count;
  final int current;
  const _DotsIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: active ? 10 : 6,
          height: active ? 10 : 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: active ? AppColors.moduleGreen : Colors.white70,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26, width: 0.5),
          ),
        );
      }),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Mapa con trazas + segmento destacado ──────────────────────────────────

class _MapaSegmento extends StatelessWidget {
  final SegmentoDetalleController controller;
  const _MapaSegmento({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: controller.mapController,
          options: MapOptions(
            initialCenter: controller.initialCenter,
            initialZoom: controller.initialZoom,
            minZoom: 5,
            maxZoom: 20,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.all),
          ),
          children: [
            TileLayer(
              urlTemplate: ApiEndpoints.pnoaWmts,
              tileProvider: CancellableNetworkTileProvider(),
              userAgentPackageName: 'com.leulit.enagas.helireport_desherbaje',
              additionalOptions: const {'User-Agent': 'helireport-desherbaje'},
            ),
            // Trazas de gasoductos (grises de fondo)
            Obx(() => PolylineLayer(
                  polylines: controller.gasoductosPolylines.toList(),
                )),
            // Segmento actual destacado
            PolylineLayer(polylines: [controller.highlightedSegment]),
          ],
        ),
        Positioned(
          bottom: 12,
          right: 12,
          child: _ZoomControls(controller: controller),
        ),
      ],
    );
  }
}

class _ZoomControls extends StatelessWidget {
  final SegmentoDetalleController controller;
  const _ZoomControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
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
    final radius = isTop
        ? const BorderRadius.vertical(top: Radius.circular(8))
        : const BorderRadius.vertical(bottom: Radius.circular(8));
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: AppColors.moduleGreen),
        ),
      ),
    );
  }
}
