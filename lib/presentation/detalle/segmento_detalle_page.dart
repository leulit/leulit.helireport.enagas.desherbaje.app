import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chat_bubbles/chat_bubbles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/api_endpoints.dart';
import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../core/extensions.dart';
import '../../core/widgets/my_current_location_layer.dart';
import '../../data/model/mensaje_entity.dart';
import '../../domain/entities/imagen_segmento_entity.dart';
import '../../domain/entities/segmento_entity.dart';
import 'segmento_detalle_controller.dart';
import 'segmento_media_item.dart';
import '../camera/video_player_page.dart';

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
      automaticallyImplyLeading: false,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 2, color: const Color(0xFFA5D6A7)),
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
          icon: const Icon(Icons.cloud_upload_outlined,
              color: AppColors.moduleGreen),
          tooltip: 'Forzar envío a nube',
          onPressed: () => Get.toNamed(AppRoutes.forzarEnvio),
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
              _MensajesTab(controller: controller),
              _MediaCarousel(
                controller: controller,
                tipo: TipoFoto.antes,
              ),
              _MediaCarousel(
                controller: controller,
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

/// Estados seleccionables partiendo de [origen]: el propio estado
/// (permanecer) + sus transiciones permitidas (matriz SSOT en
/// `EstadoActividad.transicionesPermitidas`). Filtra por el estado ORIGINAL
/// cargado, no por el valor que el usuario va seleccionando, para que el valor
/// elegido siempre pertenezca a la lista mostrada.
List<EstadoActividad> _estadosEditables(EstadoActividad origen) =>
    EstadoActividad.values.where(origen.puedeIrA).toList();

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

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
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
                          Text(lengthText,
                              style: const TextStyle(fontSize: 13)),
                          const Text('  -  ',
                              style:
                                  TextStyle(fontSize: 13, color: Colors.grey)),
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
                  values: _estadosEditables(controller.segmento.estado),
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
              ],
            ),
          ),
        ),
        _GuardarBar(controller: controller),
      ],
    );
  }
}

/// Barra inferior fija con el botón "Guardar", pinneada bajo el `Expanded`
/// scrollable de `_DatosTab` para que sea siempre visible sin hacer scroll.
class _GuardarBar extends StatelessWidget {
  final SegmentoDetalleController controller;
  const _GuardarBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: SizedBox(
        width: double.infinity,
        child: Obx(() => ElevatedButton.icon(
              onPressed: controller.isSaving.value ? null : controller.guardar,
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
                isExpanded: true,
                decoration: InputDecoration(
                  prefixIcon:
                      Icon(icon, color: AppColors.moduleGreen, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: values
                    .map((v) => DropdownMenuItem<T>(
                          value: v,
                          child: Text(labelOf(v),
                              overflow: TextOverflow.ellipsis,
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
  final SegmentoDetalleController controller;
  const _MensajesTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoadingMensajes.value && controller.mensajes.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.segmento.id == null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Guarda el segmento para ver mensajes',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
        );
      }
      final currentUserId = controller.user.value?.id ?? 0;
      return Column(
        children: [
          Expanded(
            child: controller.mensajes.isEmpty
                ? const _EmptyState(
                    icon: Icons.chat_bubble_outline,
                    message: 'Sin mensajes',
                  )
                : ListView.builder(
                    controller: controller.mensajesScrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    reverse: true,
                    itemCount: controller.mensajes.length,
                    itemBuilder: (_, i) {
                      final msg = controller.mensajes[i];
                      return _MensajeBubble(
                        mensaje: msg,
                        isSender: msg.enviadoPor == currentUserId,
                      );
                    },
                  ),
          ),
          _MensajeInput(controller: controller),
        ],
      );
    });
  }
}

class _MensajeBubble extends StatelessWidget {
  final MensajeSegmentoEntity mensaje;
  final bool isSender;

  const _MensajeBubble({required this.mensaje, required this.isSender});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('dd/MM HH:mm').format(mensaje.createdAt);
    final author = isSender
        ? null
        : (mensaje.enviadoPor != null
            ? 'Operador #${mensaje.enviadoPor}'
            : 'Operador');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Column(
        crossAxisAlignment:
            isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (author != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 2),
              child: Text(
                author,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          BubbleSpecialThree(
            text: mensaje.mensaje,
            color: isSender ? AppColors.moduleGreen : const Color(0xFFE8E8EE),
            tail: true,
            isSender: isSender,
            textStyle: TextStyle(
              color: isSender ? Colors.white : Colors.black87,
              fontSize: 14,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 2),
            child: Text(
              timeStr,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class _MensajeInput extends StatelessWidget {
  final SegmentoDetalleController controller;
  const _MensajeInput({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller.textMensajeController,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => controller.sendMensaje(),
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje…',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(
                    color: AppColors.moduleGreen,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Obx(() => IconButton(
                onPressed: controller.isSendingMensaje.value
                    ? null
                    : controller.sendMensaje,
                icon: controller.isSendingMensaje.value
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                color: AppColors.moduleGreen,
                tooltip: 'Enviar',
              )),
        ],
      ),
    );
  }
}

// ─── Tab Imágenes ───────────────────────────────────────────────────────────

/// Carrusel + botón de captura de fotos para un único [TipoFoto] (antes /
/// después). Usa [PageView] con un indicador de puntos. Lee de
/// `controller.imagenes` (Rx) para reaccionar a las capturas nuevas.
class _MediaCarousel extends StatefulWidget {
  final SegmentoDetalleController controller;
  final TipoFoto tipo;

  const _MediaCarousel({required this.controller, required this.tipo});

  @override
  State<_MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<_MediaCarousel> {
  late final PageController _pageController = PageController();
  int _current = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esAntes = widget.tipo == TipoFoto.antes;
    return Column(
      children: [
        Expanded(
          child: Obx(() {
            final media = widget.controller.mediaPorTipo(widget.tipo);
            if (media.isEmpty) {
              return _EmptyState(
                icon: Icons.perm_media_outlined,
                message: 'Sin fotos ni vídeos ${esAntes ? 'antes' : 'después'}',
              );
            }
            // Reposicionar el indicador si la lista cambió y desbordamos.
            if (_current >= media.length) _current = media.length - 1;
            return Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  itemCount: media.length,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemBuilder: (_, i) {
                    final item = media[i];
                    return item.isVideo
                        ? _VideoSlide(item: item)
                        : _CarouselSlide(item: item);
                  },
                ),
                // Contador "n / N" arriba-derecha — siempre visible.
                Positioned(
                  top: 10,
                  right: 10,
                  child: _CountChip(
                    current: _current + 1,
                    total: media.length,
                  ),
                ),
                if (media.length > 1)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: _DotsIndicator(
                      count: media.length,
                      current: _current,
                    ),
                  ),
              ],
            );
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => widget.controller.capturarMedia(widget.tipo),
              icon: const Icon(Icons.add_a_photo),
              label: Text(
                esAntes
                    ? 'Añadir foto/vídeo antes'
                    : 'Añadir foto/vídeo después',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CarouselSlide extends StatelessWidget {
  final SegmentoMediaItem item;
  const _CarouselSlide({required this.item});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: _image()),
        if (item.onDelete != null)
          Positioned(
              top: 10, left: 10, child: _DeleteBadge(onTap: item.onDelete!)),
      ],
    );
  }

  Widget _image() {
    final url = item.remoteUrl;
    if (url != null && url.isNotEmpty) {
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
    // Sin URL remota → la imagen aún vive solo en disco local.
    final local = item.localPath;
    if (local != null && local.isNotEmpty) {
      return Container(
        color: Colors.black,
        child: Image.file(File(local), fit: BoxFit.contain),
      );
    }
    return Container(
      color: Colors.grey.shade200,
      child: const Center(
        child: Icon(Icons.image_not_supported, color: Colors.grey, size: 48),
      ),
    );
  }
}

/// Slide de vídeo en el carrusel: póster negro con botón play. Al tocar abre
/// el reproductor a pantalla completa: usa el fichero local si existe, y si no
/// la url remota (vídeo ya en la nube). Si no hay ninguna fuente, avisa.
class _VideoSlide extends StatelessWidget {
  final SegmentoMediaItem item;
  const _VideoSlide({required this.item});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _open,
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.videocam, color: Colors.white24, size: 96),
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.play_arrow, color: Colors.white, size: 44),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.filename,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    item.isSubida
                        ? Icons.cloud_done
                        : Icons.cloud_upload_outlined,
                    color: item.isSubida
                        ? AppColors.moduleGreen
                        : Colors.orangeAccent,
                    size: 18,
                  ),
                ],
              ),
            ),
            if (item.onDelete != null)
              Positioned(
                top: 10,
                left: 10,
                child: _DeleteBadge(onTap: item.onDelete!),
              ),
          ],
        ),
      ),
    );
  }

  void _open() {
    final local = item.localPath;
    if (local != null && local.isNotEmpty && File(local).existsSync()) {
      Get.to<void>(() => VideoPlayerPage(path: local));
      return;
    }
    final url = item.remoteUrl;
    if (url != null && url.isNotEmpty) {
      final full = url.startsWith('http') ? url : '${ApiEndpoints.baseUrl}$url';
      Get.to<void>(() => VideoPlayerPage.network(full));
      return;
    }
    Get.snackbar(
      'Video no disponible',
      'No hay fuente reproducible para este video.',
      snackPosition: SnackPosition.BOTTOM,
    );
  }
}

class _DeleteBadge extends StatelessWidget {
  final VoidCallback onTap;
  const _DeleteBadge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.delete_outline, color: Colors.white, size: 22),
        ),
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
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(count, (i) {
            final active = i == current;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: active ? 18 : 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: active ? AppColors.moduleGreen : Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final int current;
  final int total;
  const _CountChip({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            '$current / $total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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
            initialCameraFit: controller.initialCameraFit,
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
            Obx(() => PolylineLayer(
                  polylines: [controller.highlightedSegment.value],
                )),
            MyCurrentLocationLayer(),
          ],
        ),
        Positioned(
          bottom: 12,
          right: 12,
          child: _ZoomControls(controller: controller),
        ),
        Positioned(
          bottom: 12,
          left: 12,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            elevation: 3,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: controller.abrirEdicionExtremos,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.edit_location_alt_outlined,
                        size: 18, color: AppColors.moduleGreen),
                    SizedBox(width: 6),
                    Text(
                      'Editar extremos',
                      style: TextStyle(
                        color: AppColors.moduleGreen,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
