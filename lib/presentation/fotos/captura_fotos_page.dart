import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chat_bubbles/chat_bubbles.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:leulit_flutter_fullresponsive/leulit_flutter_fullreponsive.dart';
import '../../core/app_theme.dart';
import '../../domain/entities/actividad_entity.dart';
import '../../data/model/mensaje_entity.dart';
import '../../domain/entities/imagen_segmento_entity.dart';
import '../../domain/entities/segmento_entity.dart';
import 'captura_fotos_controller.dart';

class CapturaFotosPage extends GetView<CapturaFotosController> {
  const CapturaFotosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Segmento #${controller.segmento.id}'),
          backgroundColor: const Color(0xFF388E3C),
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            // 1. Contexto completo del segmento
            _HeaderSegmento(
              segmento: controller.segmento,
              controller: controller,
            ),
            // 2. Selector de tipo de foto (TRAS el contexto, no antes)
            Container(
              color: const Color(0xFF2E7D32),
              child: const TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                tabs: [
                  Tab(icon: Icon(Icons.message_rounded, size: 18), text: 'Mensajes'),
                  Tab(icon: Icon(Icons.camera_enhance, size: 18), text: 'Antes'),
                  Tab(icon: Icon(Icons.check_circle, size: 18), text: 'Después'),
                ],
              ),
            ),
            // 3. Progreso de subida (si activo)
            Obx(() {
              if (!controller.isUploading.value) return const SizedBox.shrink();
              return Container(
                color: Colors.green.shade50,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: controller.uploadTotal.value > 0
                          ? controller.uploadCurrent.value /
                              controller.uploadTotal.value
                          : null,
                      color: const Color(0xFF388E3C),
                      backgroundColor: Colors.green.shade100,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Subiendo ${controller.uploadCurrent.value}/${controller.uploadTotal.value}...',
                      style: const TextStyle(fontSize: 11, color: Colors.green),
                    ),
                  ],
                ),
              );
            }),
            // 4. Contenido de cada tab
            Expanded(
              child: TabBarView(
                children: [
                  _buildTabMensajes(controller),
                  _FotosTab(tipo: TipoFoto.antes, controller: controller),
                  _FotosTab(tipo: TipoFoto.despues, controller: controller),
                ],
              ),
            ),
            // 5. Acción principal
            _Footer(controller: controller),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTabMensajes(CapturaFotosController controller) {
    return Obx(() {
      controller.updUI.value;
      return Column(
        children: [
          Expanded(
            child: controller.mensajes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text(
                          'Sin mensajes',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
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
                        isSender: msg.senderUserId == 0,
                      );
                    },
                  ),
          ),
          _buildMensajeInput(controller),
        ],
      );
    });
  }

  Widget _buildMensajeInput(CapturaFotosController controller) {
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
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje…',
                hintStyle:
                    TextStyle(fontSize: 13, color: Colors.grey.shade400),
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
                  borderSide: BorderSide(color: Colors.blue.shade400),
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => controller.sendMensaje(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: controller.sendMensaje,
            icon: const Icon(Icons.send_rounded),
            color: Colors.blue.shade600,
            tooltip: 'Enviar',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header — toda la información relevante del segmento
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderSegmento extends StatelessWidget {
  final SegmentoEntity segmento;
  final CapturaFotosController controller;

  const _HeaderSegmento({
    required this.segmento,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {

    return Container(
      width: double.infinity,
      color: const Color(0xFFE8F5E9),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila 1: nombre del segmento + badge de estado
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.route_outlined,
                  size: 15, color: Color(0xFF388E3C)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  segmento.descripcion ??  '...',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B5E20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Fila 2: tipo de actividad + tipo de instalación + fecha
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _Chip(
                icon: Icons.eco_outlined,
                label: segmento.tipoActividad.etiqueta,
                color: const Color(0xFF388E3C),
              ),
              Obx(() {
                final estado = controller.estadoSegmento.value;
                final bgColor = AppColors.accentForEstado(estado);
                final txtColor = AppColors.textOnAccentForEstado(estado);
                return Container(
                  width: 0.4.w,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<EstadoActividad>(
                      value: estado,
                      isDense: true,
                      icon: Icon(Icons.arrow_drop_down, size: 14, color: txtColor),
                      dropdownColor: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: txtColor,
                      ),
                      selectedItemBuilder: (_) => EstadoActividad.values
                          .map((e) => Text(
                                e.etiqueta,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: txtColor,
                                ),
                              ))
                          .toList(),
                      items: EstadoActividad.values
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: AppColors.accentForEstado(e),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      e.etiqueta,
                                      style: const TextStyle(
                                          fontSize: 13, color: Colors.black87),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                      onChanged: (e) {
                        if (e != null) controller.cambiarEstadoSegmento(e);
                      },
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 6),
          // Fila 3: métricas — longitud, superficie, PK
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
              SizedBox(width: 0.025.w),
              /*
              Row(
                children: [
                  _Chip(
                    icon: Icons.calendar_today_outlined,
                    label: dateFormat.format(actividad.fechaInicio),
                    color: Colors.blueGrey,
                  ),
                  SizedBox(width: 0.025.w),
                  _Chip(
                    icon: Icons.calendar_today_outlined,
                    label: dateFormat.format(actividad.fechaFin),
                    color: Colors.blueGrey,
                  ),
                ],
              ),
              */
            ],
          ),
        ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Tab de fotos
// ─────────────────────────────────────────────────────────────────────────────

class _FotosTab extends StatelessWidget {
  final TipoFoto tipo;
  final CapturaFotosController controller;

  const _FotosTab({required this.tipo, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final imgs = tipo == TipoFoto.antes
          ? controller.imagenesAntes
          : controller.imagenesDespues;
      final mockUrls = tipo == TipoFoto.antes
          ? controller.mockFotosAntes
          : controller.mockFotosDespues;

      final hasReal = imgs.isNotEmpty;
      final hasMock = mockUrls.isNotEmpty;

      return Column(
        children: [
          Expanded(
            child: !hasReal && !hasMock
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tipo == TipoFoto.antes
                              ? Icons.camera_enhance_outlined
                              : Icons.check_circle_outline,
                          size: 56,
                          color: Colors.grey.shade200,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          tipo == TipoFoto.antes
                              ? 'Sin fotos del estado anterior'
                              : 'Sin fotos del estado posterior',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pulsa el botón para tomar una foto',
                          style: TextStyle(
                              color: Colors.grey.shade300, fontSize: 11),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 2,
                      mainAxisSpacing: 2,
                    ),
                    itemCount: hasReal ? imgs.length : mockUrls.length,
                    itemBuilder: (context, index) => hasReal
                        ? _PhotoTile(
                            imagen: imgs[index],
                            onDelete: () => controller.deleteImagen(imgs[index]),
                          )
                        : _MockPhotoTile(url: mockUrls[index]),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_a_photo),
                label: Text(
                  tipo == TipoFoto.antes
                      ? 'Añadir foto de antes'
                      : 'Añadir foto de después',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF388E3C),
                  side: const BorderSide(color: Color(0xFF388E3C)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => controller.capturePhoto(tipo),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _MockPhotoTile extends StatelessWidget {
  final String url;

  const _MockPhotoTile({required this.url});

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: Colors.grey.shade100),
      errorWidget: (_, __, ___) =>
          const ColoredBox(color: Color(0xFFEEEEEE),
              child: Icon(Icons.broken_image, color: Colors.grey)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Footer
// ─────────────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final CapturaFotosController controller;

  const _Footer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Obx(
          () => Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.pendientes > 0)
                    Text(
                      '${controller.pendientes} pendiente(s) de subir',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.orange),
                    ),
                  Text(
                    '${controller.subidas} foto(s) subida(s)',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF388E3C)),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar y volver'),
                onPressed: controller.isUploading.value
                    ? null
                    : controller.guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF388E3C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile de foto individual
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoTile extends StatelessWidget {
  final ImagenSegmentoEntity imagen;
  final VoidCallback onDelete;

  const _PhotoTile({required this.imagen, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        imagen.remoteUrl != null
            ? CachedNetworkImage(
                imageUrl: imagen.remoteUrl!,
                fit: BoxFit.cover,
              )
            : Image.file(File(imagen.localPath), fit: BoxFit.cover),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onDelete,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
        if (imagen.syncStatus == SyncStatus.uploading)
          const Center(
              child: CircularProgressIndicator(color: Colors.white)),
        if (imagen.syncStatus == SyncStatus.uploaded)
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF388E3C),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.cloud_done,
                  size: 12, color: Colors.white),
            ),
          ),
        if (imagen.syncStatus == SyncStatus.error)
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.warning,
                  size: 12, color: Colors.white),
            ),
          ),
      ],
    );
  }
}


class _MensajeBubble extends StatelessWidget {
  final MensajeEntity mensaje;
  final bool isSender;

  const _MensajeBubble({required this.mensaje, required this.isSender});

  @override
  Widget build(BuildContext context) {
    final timeStr = mensaje.sentAt != null
        ? DateFormat('HH:mm').format(mensaje.sentAt!)
        : '';
    return Column(
      crossAxisAlignment: isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        BubbleSpecialThree(
          text: mensaje.mensaje,
          color: isSender ? const Color(0xFF1B97F3) : const Color(0xFFE8E8EE),
          tail: true,
          isSender: isSender,
          textStyle: TextStyle(
            color: isSender ? Colors.white : Colors.black87,
            fontSize: 13,
          ),
        ),
        if (timeStr.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
              left: isSender ? 0 : 16,
              right: isSender ? 16 : 0,
              bottom: 4,
            ),
            child: Text(
              timeStr,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ),
      ],
    );
  }
}

