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
import '../../core/app_typed_actions.dart';
import '../../core/extensions.dart';
import '../../core/services/api_security_service.dart';
import '../../core/widgets/my_current_location_layer.dart';
import '../../data/model/mensaje_entity.dart';
import '../../domain/entities/imagen_segmento_entity.dart';
import '../../domain/entities/segmento_entity.dart';
import 'media_gis_layer.dart';
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
            const _GuardarBar(),
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
    );
  }
}

/// Barra de acciones global bajo el panel de tabs, visible en los 4 tabs.
/// Autónoma: no depende del controller. Lee el tab activo de
/// [DefaultTabController] y emite TypedActions; el controller las escucha.
class _GuardarBar extends StatefulWidget {
  const _GuardarBar();

  @override
  State<_GuardarBar> createState() => _GuardarBarState();
}

class _GuardarBarState extends State<_GuardarBar> {
  TabController? _tab;
  int _index = 0;
  bool _saving = false;
  String? _savingHandlerId;

  @override
  void initState() {
    super.initState();
    _savingHandlerId = AppTypedActions.savingChanged.on((event) {
      if (mounted) setState(() => _saving = event.data ?? false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final t = DefaultTabController.of(context);
    if (t != _tab) {
      _tab?.removeListener(_onTab);
      _tab = t;
      _index = t.index;
      _tab?.addListener(_onTab);
    }
  }

  void _onTab() {
    final t = _tab;
    if (t == null || t.index == _index) return;
    if (mounted) setState(() => _index = t.index);
  }

  @override
  void dispose() {
    _tab?.removeListener(_onTab);
    final id = _savingHandlerId;
    if (id != null) AppTypedActions.savingChanged.off(id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showMedia = _index == 2 || _index == 3;
    // Editar extremos (geometría) solo cuando el segmento está en "contratista":
    // es el estado en el que el operario de campo trabaja la tarea.
    final showExtremos = _index == 0 &&
        Get.find<SegmentoDetalleController>().segmento.estado ==
            EstadoActividad.contratista;
    final tipo = _index == 3 ? TipoFoto.despues : TipoFoto.antes;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          _guardarButton(),
          if (showExtremos) ...[
            const SizedBox(width: 8),
            Expanded(child: _extremosButton()),
          ],
          if (showMedia) ...[
            const SizedBox(width: 8),
            Expanded(child: _mediaButton(tipo)),
          ],
        ],
      ),
    );
  }

  Widget _guardarButton() {
    return ElevatedButton.icon(
      onPressed:
          _saving ? null : () => AppTypedActions.guardarRequested.dispatch(),
      icon: _saving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.check, size: 18),
      label: const Text('Guardar'),
    );
  }

  Widget _extremosButton() {
    return ElevatedButton.icon(
      onPressed: () => AppTypedActions.editarExtremosRequested.dispatch(),
      icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
      label: const Text('Editar extremos', maxLines: 1),
    );
  }

  Widget _mediaButton(TipoFoto tipo) {
    return ElevatedButton.icon(
      onPressed: () => AppTypedActions.capturaRequested.dispatch(data: tipo),
      icon: const Icon(Icons.add_a_photo, size: 18),
      label: const Text('Foto/vídeo', maxLines: 1),
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

  /// TabController de la página; se usa para gatear el dispatch de GIS a la
  /// pestaña visible (Antes=2 / Después=3). Sin gate, la pestaña oculta —que
  /// el TabBarView también construye— pisaría el evento de la visible.
  TabController? _tab;
  bool _wasActive = false;

  int get _myTabIndex => widget.tipo == TipoFoto.antes ? 2 : 3;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final t = DefaultTabController.of(context);
    if (t != _tab) {
      _tab?.removeListener(_onTab);
      _tab = t;
      _wasActive = t.index == _myTabIndex;
      _tab?.addListener(_onTab);
      // Montaje ya-activo (tap directo 0→2/3): el índice del TabController
      // salta antes de que este State se monte, así que `_onTab` no ve el
      // flanco de subida. Disparo inicial post-frame para encuadrar el mapa
      // con la primera media al acceder por primera vez a la pestaña.
      if (_wasActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _tab?.index == _myTabIndex) _dispatchActive();
        });
      }
    }
  }

  /// Al entrar en esta pestaña (flanco a activa) emite el GIS de la media
  /// visible. Solo en el flanco de subida para no re-emitir en cada notify.
  void _onTab() {
    final t = _tab;
    if (t == null) return;
    final isActive = t.index == _myTabIndex;
    if (isActive && !_wasActive) _dispatchActive();
    _wasActive = isActive;
  }

  @override
  void dispose() {
    _tab?.removeListener(_onTab);
    _pageController.dispose();
    super.dispose();
  }

  /// Emite [AppTypedActions.mediaGisActivada] con el `gis_json` de la media
  /// activa (índice [_current]) de este [TipoFoto]. gis_json null si la media
  /// no tiene GIS; clientId vacío si no hay media. Solo debe llamarse cuando
  /// esta pestaña es la visible.
  void _dispatchActive() {
    final media = widget.controller.mediaPorTipo(widget.tipo);
    final i = _current;
    final item = (i >= 0 && i < media.length) ? media[i] : null;
    AppTypedActions.mediaGisActivada.dispatch(
      data: MediaGisActivada(
        gisJson: item?.gisJson,
        tipo: widget.tipo,
        clientId: item?.clientId ?? '',
        isVideo: item?.isVideo ?? false,
      ),
    );
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
                  onPageChanged: (i) {
                    setState(() => _current = i);
                    if (_tab?.index == _myTabIndex) _dispatchActive();
                  },
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
    final id = item.remoteId;
    if (id != null) {
      // w=0,h=0 → original. La media SIEMPRE exige credencial; aquí la petición
      // la hace la app, así que va HMAC en cabeceras (la firma en query se
      // reserva para las urls que se entregan a un reproductor).
      final fullUrl = ApiEndpoints.segmentoThumb(id, 0, 0);
      return Container(
        color: Colors.black,
        child: CachedNetworkImage(
          imageUrl: fullUrl,
          httpHeaders: ApiSecurityService.buildHmacHeaders(
            'GET',
            Uri.parse(fullUrl).path,
          ),
          fit: BoxFit.contain,
          placeholder: (_, __) =>
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          errorWidget: (_, __, ___) =>
              const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
        ),
      );
    }
    // Sin id remoto → la imagen aún vive solo en disco local.
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
/// la url remota firmada (vídeo ya en la nube). Si no hay ninguna fuente, avisa.
///
/// Un vídeo de nube aún en conversión no se ofrece como reproducible: su url
/// devuelve 404 hasta `status: disponible`, así que se pinta "procesando" y el
/// tap no abre el reproductor. La copia local, si existe, siempre gana: se
/// reproduce sin esperar al servidor.
class _VideoSlide extends StatelessWidget {
  final SegmentoMediaItem item;
  const _VideoSlide({required this.item});

  bool get _hasLocalPath {
    final local = item.localPath;
    return local != null && local.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    // La copia local no depende del servidor: si la hay, el estado de
    // conversión es irrelevante.
    final procesando = !_hasLocalPath && item.isMediaProcesando;
    final fallido = !_hasLocalPath && item.isMediaError;
    return GestureDetector(
      onTap: (procesando || fallido) ? null : _open,
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.videocam, color: Colors.white24, size: 96),
            if (procesando)
              const _VideoEstadoBadge(
                icon: Icons.hourglass_top,
                label: 'Procesando…',
                detail: 'El vídeo estará disponible cuando el servidor termine '
                    'de convertirlo.',
                color: Colors.orangeAccent,
              )
            else if (fallido)
              const _VideoEstadoBadge(
                icon: Icons.error_outline,
                label: 'Conversión fallida',
                detail: 'El servidor no pudo procesar este vídeo.',
                color: Colors.redAccent,
              )
            else
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
    final id = item.remoteId;
    if (id != null && item.isMediaDisponible) {
      // Firma en query, no en cabeceras: el reproductor fija la url una vez y
      // cada seek reusa el mismo `ts`, cosa que la ventana de ±5 min del HMAC
      // de cabeceras no sobrevive. Este endpoint acepta 2 h por eso mismo.
      final signed = ApiSecurityService.buildSignedMediaUrl(
        ApiEndpoints.segmentoThumb(id, 0, 0),
      );
      Get.to<void>(() => VideoPlayerPage.network(signed));
      return;
    }
    Get.snackbar(
      'Vídeo no disponible',
      'No hay fuente reproducible para este vídeo.',
      snackPosition: SnackPosition.BOTTOM,
    );
  }
}

/// Estado no reproducible de un vídeo de nube (en conversión o fallido).
class _VideoEstadoBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final Color color;

  const _VideoEstadoBadge({
    required this.icon,
    required this.label,
    required this.detail,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 44),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
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
            // Georreferencia de la media activa en el carrusel (foto/vídeo).
            const MediaGisLayer(),
            MyCurrentLocationLayer(
              alignPositionStream: controller.alignEnDispositivoStream,
            ),
          ],
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
              onTap: () =>
                  AppTypedActions.centrarEnDispositivoRequested.dispatch(),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.my_location,
                    size: 22, color: AppColors.moduleGreen),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
