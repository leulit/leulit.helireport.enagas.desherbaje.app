import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../core/extensions.dart';
import '../../core/widgets/filtros_segmentos_bar.dart';
import '../../domain/entities/segmento_entity.dart';
import '../widgets/logout_button.dart';
import '../widgets/track_record_button.dart';
import 'segmentos_list_controller.dart';

class SegmentosListPage extends GetView<SegmentosListController> {
  const SegmentosListPage({super.key});

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
          padding: EdgeInsets.all(8.0),
          child: Icon(Icons.eco, color: AppColors.moduleGreen),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined, color: AppColors.moduleGreen),
            tooltip: 'Ver mapa',
            onPressed: () => Get.toNamed(AppRoutes.mapa),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined,
                color: AppColors.moduleGreen),
            tooltip: 'Forzar envío',
            onPressed: () => Get.toNamed(AppRoutes.forzarEnvio),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.moduleGreen),
            onPressed: controller.loadSegmentos,
          ),
          const TrackRecordButton(),
          const LogoutButton(),
        ],
      ),
      body: Column(
        children: [
          _FiltrosBar(controller: controller),
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
                child: _GroupedByCt(controller: controller),
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
  final SegmentosListController controller;
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
          TextField(
            controller: controller.descripcionCtrl,
            onChanged: (v) => controller.filterDescripcion.value = v,
            decoration: InputDecoration(
              hintText: 'Buscar por descripción…',
              hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
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
          const SizedBox(height: 6),
          Obx(() => SegmentoFiltrosRow(
                rxEstado: controller.selectedEstado,
                estadoItems: const [
                  EstadoActividad.propuesta,
                  EstadoActividad.contratista,
                  EstadoActividad.validada,
                  EstadoActividad.ejecucion,
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

// ─── Listado agrupado por CT con acordeón ────────────────────────────────────

class _GroupedByCt extends StatelessWidget {
  final SegmentosListController controller;
  const _GroupedByCt({required this.controller});

  @override
  Widget build(BuildContext context) {
    final grouped = controller.groupedByCt;
    final ctNames = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: ctNames.length,
      itemBuilder: (_, i) {
        final ct = ctNames[i];
        final list = grouped[ct]!;
        final totalLongitud = list.fold<double>(0, (s, e) => s + e.longitud);
        final totalSuperficie =
            list.fold<double>(0, (s, e) => s + e.superficie);

        return Obx(() {
          final isExpanded = controller.expandedCt.value == ct;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFA5D6A7), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _CtHeader(
                  ctName: controller.ctLabel(ct),
                  total: list.length,
                  totalLongitud: totalLongitud,
                  totalSuperficie: totalSuperficie,
                  isExpanded: isExpanded,
                  onTap: () => controller.toggleCtExpanded(ct),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      children: [
                        for (final s in list)
                          _SegmentCard(
                            segmento: s,
                            onTap: () => controller.goToDetalle(s),
                          ),
                      ],
                    ),
                  ),
                  crossFadeState: isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}

class _CtHeader extends StatelessWidget {
  final String ctName;
  final int total;
  final double totalLongitud;
  final double totalSuperficie;
  final bool isExpanded;
  final VoidCallback onTap;

  const _CtHeader({
    required this.ctName,
    required this.total,
    required this.totalLongitud,
    required this.totalSuperficie,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // El color de fondo indica el estado del acordión: más intenso cuando
    // está abierto, claro cuando está cerrado. Sustituye al chevron para
    // que toda la información quepa en una sola línea.
    final bg =
        isExpanded ? const Color(0xFFC8E6C9) : AppColors.moduleGreenLight;
    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Badge del contador en la cabecera (sustituye al icono).
                  _HeaderBadge(value: '$total', strong: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ctName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.moduleGreenText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _HeaderBadge(
                    value:
                        '${(totalLongitud / 1000).toStringWithComma(decimals: 2)} km',
                    bold: false,
                    width: 90,
                  ),
                  const SizedBox(width: 6),
                  _HeaderBadge(
                    value:
                        '${totalSuperficie.toStringWithComma(decimals: 0)} m²',
                    bold: false,
                    width: 90,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  final String value;
  final bool strong;
  final bool bold;
  final double? width;

  const _HeaderBadge({
    required this.value,
    this.strong = false,
    this.bold = true,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final bg = strong ? AppColors.moduleGreen : Colors.white;
    final fg = strong ? Colors.white : AppColors.moduleGreenText;
    final border = strong ? AppColors.moduleGreen : const Color(0xFFA5D6A7);

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: border),
      ),
      alignment: width == null ? null : Alignment.center,
      child: Text(
        value,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}

// ─── Tarjeta de segmento ─────────────────────────────────────────────────────

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
  final VoidCallback onTap;

  const _SegmentCard({required this.segmento, required this.onTap});

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
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right,
                              size: 18, color: Colors.grey),
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
                          _Badge(
                            prefix: 'Estado:',
                            label: segmento.estado.etiqueta,
                            color: estadoColor,
                            bg: estadoBg,
                          ),
                          const SizedBox(width: 6),
                          _Badge(
                            prefix: 'Tipo:',
                            label: segmento.tipoActividad.etiqueta,
                            color: tipoColor,
                            outlined: true,
                          ),
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
          Icon(Icons.straighten, size: 48, color: Colors.grey.shade300),
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
