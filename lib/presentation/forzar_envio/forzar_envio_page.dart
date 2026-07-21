import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../core/extensions.dart';
import '../../core/widgets/filtros_segmentos_bar.dart';
import '../../domain/entities/segmento_entity.dart';
import 'forzar_envio_controller.dart';

class ForzarEnvioPage extends GetView<ForzarEnvioController> {
  const ForzarEnvioPage({super.key});

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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.moduleGreen),
          tooltip: 'Volver',
          onPressed: Get.back,
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
      ),
      body: Column(
        children: [
          _FiltrosBar(controller: controller),
          const _ResultadoEnvioBanner(),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.moduleGreen),
                );
              }
              if (controller.error.value != null) {
                return _ErrorView(
                  message: controller.error.value!,
                  onRetry: controller.loadSegmentos,
                );
              }
              if (controller.filtradas.isEmpty) {
                return _EmptyView(
                  isFiltered: controller.segmentos.isNotEmpty,
                );
              }
              return RefreshIndicator(
                onRefresh: controller.loadSegmentos,
                color: AppColors.moduleGreen,
                child: _FlatList(controller: controller),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─── Barra de filtros ────────────────────────────────────────────────────────

class _FiltrosBar extends StatelessWidget {
  final ForzarEnvioController controller;
  const _FiltrosBar({required this.controller});

  static final _border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: Color(0xFFA5D6A7)),
  );
  static final _borderFocused = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: AppColors.moduleGreen, width: 1.5),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.moduleGreenLight,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => controller.filterDescripcion.value = v,
                  decoration: InputDecoration(
                    hintText: 'Buscar por descripción…',
                    hintStyle:
                        const TextStyle(fontSize: 13, color: Colors.grey),
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.moduleGreen, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: _border,
                    enabledBorder: _border,
                    focusedBorder: _borderFocused,
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Obx(() {
                final busy = controller.isEnviandoTodos.value;
                return ElevatedButton.icon(
                  onPressed: busy ? null : controller.enviarAllCloud,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.moduleGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: const Text('Enviar todos',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                );
              }),
            ],
          ),
          const SizedBox(height: 6),
          Obx(() => SegmentoFiltrosRow(
                rxEstado: controller.selectedEstado,
                // El controller solo carga contratista/finalizada
                // (`loadSegmentos`); ofrecer más estados nunca filtraría nada.
                estadoItems: const [
                  EstadoActividad.contratista,
                  EstadoActividad.finalizada,
                ],
                onEstado: controller.filterByEstado,
                rxTipo: controller.selectedTipo,
                onTipo: controller.filterByTipo,
                rxCt: controller.selectedCt,
                ctItems: controller.ctsDisponibles,
                ctLabel: controller.ctLabel,
                onCt: controller.filterByCt,
              )),
        ],
      ),
    );
  }
}

// ─── Resultado del último envío ─────────────────────────────────────────────

/// Banner con el desenlace del último envío. Hasta ahora `lastError` y
/// `lastDrainSummary` se calculaban y se descartaban: un envío que no subía
/// nada era indistinguible de uno correcto. Solo lee observables del
/// controller — ni `TypedAction` ni servicios en el widget.
class _ResultadoEnvioBanner extends GetView<ForzarEnvioController> {
  const _ResultadoEnvioBanner();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final error = controller.lastError.value;
      final info = controller.lastInfo.value;
      if (error.isEmpty && info.isEmpty) return const SizedBox.shrink();

      final isError = error.isNotEmpty;
      final color = isError ? const Color(0xFFC62828) : AppColors.moduleGreen;
      final bg = isError ? const Color(0xFFFFEBEE) : AppColors.moduleGreenLight;
      final summary = controller.lastDrainSummary.value;
      // Motivos reales del backend: el summary solo cuenta, `rechazos` explica.
      final motivos = controller.rechazos
          .map((r) => [
                r.statusCode == null ? null : 'HTTP ${r.statusCode}',
                r.errorMessageEs,
              ].whereType<String>().join(' — '))
          .where((m) => m.isNotEmpty)
          .toSet()
          .toList();

      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.cloud_done_outlined,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isError ? error : info,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: color),
                  tooltip: 'Cerrar aviso',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                      minWidth: 48, minHeight: 48),
                  onPressed: controller.descartarResultado,
                ),
              ],
            ),
            if (motivos.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...motivos.map(
                (m) => Padding(
                  padding: const EdgeInsets.only(left: 26, bottom: 2),
                  child: Text(
                    '• $m',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: color.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
            ],
            if (summary != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(
                  'Subidos: ${summary.succeeded} · '
                  'Reintentables: ${summary.retryable} · '
                  'Rechazados: ${summary.rejected} · '
                  'Conflictos: ${summary.conflicts}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}

// ─── Lista plana (sin agrupar por CT) ───────────────────────────────────────

class _FlatList extends StatelessWidget {
  final ForzarEnvioController controller;
  const _FlatList({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: controller.filtradas.length,
      itemBuilder: (_, i) {
        final s = controller.filtradas[i];
        return _SegmentCard(
          segmento: s,
          ctName: controller.ctLabel(s.ctname),
          controller: controller,
          onEnviar: () => controller.enviarCloud(s),
          onTap: () => Get.toNamed(AppRoutes.detalle, arguments: s),
        );
      },
    );
  }
}

// ─── Tarjeta de segmento con botón de envío ─────────────────────────────────

const Map<EstadoActividad, Color> _estadoColors = {
  EstadoActividad.propuesta: Color(0xFF78909C),
  EstadoActividad.validada: Color(0xFF1976D2),
  EstadoActividad.contratista: Color.fromARGB(255, 244, 93, 234),
  EstadoActividad.ejecucion: Color(0xFFF57C00),
  EstadoActividad.finalizada: Color(0xFF388E3C),
  EstadoActividad.cerrada: Color(0xFF546E7A),
};

const Map<EstadoActividad, Color> _estadoBgColors = {
  EstadoActividad.propuesta: Color(0xFFECEFF1),
  EstadoActividad.validada: Color(0xFFE3F2FD),
  EstadoActividad.contratista: Color(0xFFE3F2FD),
  EstadoActividad.ejecucion: Color(0xFFFFF3E0),
  EstadoActividad.finalizada: Color(0xFFE8F5E9),
  EstadoActividad.cerrada: Color(0xFFECEFF1),
};

const Map<TipoActividad, Color> _tipoColors = {
  TipoActividad.desbroceManual: Color(0xFF6D4C41),
  TipoActividad.desbroceMecanico: Color(0xFFBF360C),
  TipoActividad.tala: Color(0xFF4E342E),
  TipoActividad.resiembre: Color(0xFF558B2F),
  TipoActividad.posicionDesherbajeTraza: Color(0xFF00796B),
  TipoActividad.tratamientoAvispas: Color(0xFFF9A825),
  TipoActividad.tratamientoAranas: Color(0xFF6A1B9A),
  TipoActividad.tratamientoReptiles: Color(0xFF0277BD),
  TipoActividad.tratamientoAvispasOtros: Color(0xFFEF6C00),
  TipoActividad.tratamientoAranasOtros: Color(0xFF4527A0),
  TipoActividad.tratamientoReptilesOtros: Color(0xFF01579B),
};

class _SegmentCard extends StatelessWidget {
  final SegmentoEntity segmento;
  final String ctName;
  final ForzarEnvioController controller;
  final VoidCallback onEnviar;
  final VoidCallback onTap;

  const _SegmentCard({
    required this.segmento,
    required this.ctName,
    required this.controller,
    required this.onEnviar,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final estadoColor =
        _estadoColors[segmento.estado] ?? const Color(0xFF78909C);
    final estadoBg =
        _estadoBgColors[segmento.estado] ?? const Color(0xFFECEFF1);
    final tipoColor =
        _tipoColors[segmento.tipoActividad] ?? const Color(0xFF00796B);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: estadoColor.withValues(alpha: 0.25), width: 1),
      ),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: estadoColor.withValues(alpha: 0.7),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            segmento.id != null ? '#${segmento.id}' : 'Sin ID',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          _Metric(
                            icon: Icons.straighten,
                            label: 'Long.',
                            value:
                                '${(segmento.longitud / 1000).toStringWithComma(decimals: 2)} km',
                          ),
                          const SizedBox(width: 12),
                          _Metric(
                            icon: Icons.square_foot,
                            label: 'Sup.',
                            value:
                                '${segmento.superficie.toStringWithComma(decimals: 0)} m²',
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        segmento.descripcion.isEmpty
                            ? '....'
                            : segmento.descripcion,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade900,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.business,
                              size: 14, color: Colors.blueGrey.shade600),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              ctName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.blueGrey.shade800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if ((segmento.traza ?? '').isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Icon(Icons.timeline,
                                size: 14, color: Colors.blueGrey.shade600),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                segmento.traza!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.blueGrey.shade800,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(height: 1, color: Colors.grey.shade200),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _Badge(
                                  prefix: 'Estado:',
                                  label: segmento.estado.etiqueta,
                                  color: estadoColor,
                                  bg: estadoBg,
                                ),
                                _Badge(
                                  prefix: 'Tipo:',
                                  label: segmento.tipoActividad.etiqueta,
                                  color: tipoColor,
                                  outlined: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Obx propio: el `itemBuilder` del ListView corre en
                          // layout, fuera del build del Obx de la página, así
                          // que leer `enviandoIds` allí no registra dependencia
                          // y el spinner nunca se pintaría.
                          Obx(() {
                            final isSending = controller.enviandoIds
                                .contains(segmento.clientId);
                            return ElevatedButton.icon(
                              onPressed: isSending ? null : onEnviar,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.moduleGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                minimumSize: const Size(0, 32),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: isSending
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.cloud_upload_outlined,
                                      size: 14),
                              label: const Text('Enviar',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.blueGrey.shade400),
        const SizedBox(width: 4),
        Text('$label ',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade800,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String prefix;
  final String label;
  final Color color;
  final Color? bg;
  final bool outlined;

  const _Badge({
    required this.prefix,
    required this.label,
    required this.color,
    this.bg,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: outlined
            ? Colors.transparent
            : (bg ?? color.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: color.withValues(alpha: outlined ? 0.45 : 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(prefix,
              style:
                  TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7))),
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

// ─── Estados auxiliares ──────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final bool isFiltered;
  const _EmptyView({required this.isFiltered});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text(
            isFiltered
                ? 'Sin resultados para el filtro activo'
                : 'Sin segmentos',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 8),
          Text(message),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
