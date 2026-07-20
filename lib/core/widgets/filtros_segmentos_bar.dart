import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../domain/entities/segmento_entity.dart';

/// Paleta de los filtros de segmento, compartida por listado, mapa y forzar
/// envío para que un mismo estado/tipo se vea igual en toda la app.
const Map<EstadoActividad, Color> kEstadoFilterColors = {
  EstadoActividad.propuesta: Color(0xFF78909C),
  EstadoActividad.validada: Color(0xFF1976D2),
  EstadoActividad.contratista: Color.fromARGB(255, 241, 70, 219),
  EstadoActividad.ejecucion: Color(0xFFF57C00),
  EstadoActividad.finalizada: Color(0xFF388E3C),
  EstadoActividad.cerrada: Color(0xFF546E7A),
};

const Map<TipoActividad, Color> kTipoFilterColors = {
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

const Color kEstadoFilterGroupColor = Color(0xFF455A64);
const Color kTipoFilterGroupColor = Color(0xFF2E7D32);
const Color kCtFilterGroupColor = Color(0xFF1565C0);

/// Chip de filtro compacto.
///
/// Sustituye al `DropdownButton` anterior: aquel dimensionaba su caja por el
/// ítem MÁS LARGO del menú, así que "Posición desherbaje traza" reventaba la
/// fila y recortaba los filtros vecinos. Aquí el chip solo pinta la selección
/// actual (elipsada) y el menú se abre en un overlay de ancho independiente,
/// de modo que el ancho del chip lo decide la fila, no el catálogo.
///
/// Se indexa por posición (`-1` = "Todos") porque `PopupMenuButton` no puede
/// distinguir un valor `null` seleccionado de un menú descartado.
class FilterChipDropdown<T> extends StatelessWidget {
  final IconData icon;
  final Color groupColor;
  final Rx<T?> rxValue;
  final List<T> items;
  final String Function(T) itemLabel;
  final Color Function(T) itemColor;
  final void Function(T?) onChanged;

  /// Texto del chip y del ítem de reset cuando no hay filtro aplicado.
  final String allLabel;

  /// Texto mostrado cuando [items] está vacío (aún sin datos cargados).
  final String emptyLabel;

  const FilterChipDropdown({
    super.key,
    required this.icon,
    required this.groupColor,
    required this.rxValue,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    Color Function(T)? itemColor,
    this.allLabel = 'Todos',
    this.emptyLabel = 'Sin datos',
  }) : itemColor = itemColor ?? _defaultItemColor;

  static Color _defaultItemColor(Object? _) => kEstadoFilterGroupColor;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selected = rxValue.value;
      final active = selected != null;
      final color = active ? itemColor(selected) : groupColor;
      final label = active
          ? itemLabel(selected)
          : (items.isEmpty ? emptyLabel : allLabel);

      return PopupMenuButton<int>(
        tooltip: label,
        position: PopupMenuPosition.under,
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        // -1 = "Todos": el índice evita la ambigüedad null-vs-descartado.
        onSelected: (i) => onChanged(i < 0 ? null : items[i]),
        itemBuilder: (_) => [
          PopupMenuItem<int>(
            value: -1,
            height: 40,
            child: Row(
              children: [
                Icon(Icons.clear_all, size: 16, color: groupColor),
                const SizedBox(width: 8),
                Text(allLabel,
                    style: TextStyle(fontSize: 13, color: groupColor)),
              ],
            ),
          ),
          for (var i = 0; i < items.length; i++)
            PopupMenuItem<int>(
              value: i,
              height: 40,
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: itemColor(items[i]),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      itemLabel(items[i]),
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 13,
                        color: itemColor(items[i]),
                        fontWeight:
                            selected == items[i] ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: active ? 0.14 : 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: active ? 0.55 : 0.25),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.arrow_drop_down, size: 16, color: color),
            ],
          ),
        ),
      );
    });
  }
}

/// Fila de filtros Estado / Tipo / CT compartida por listado, mapa y forzar
/// envío. Los tres chips reparten el ancho a partes iguales, así que la fila
/// nunca desborda: el texto largo se elipsa dentro de su chip.
class SegmentoFiltrosRow extends StatelessWidget {
  final Rx<EstadoActividad?> rxEstado;
  final List<EstadoActividad> estadoItems;
  final void Function(EstadoActividad?) onEstado;

  final Rx<TipoActividad?> rxTipo;
  final void Function(TipoActividad?) onTipo;

  final Rx<String?> rxCt;
  final List<String> ctItems;
  final String Function(String) ctLabel;
  final void Function(String?) onCt;

  const SegmentoFiltrosRow({
    super.key,
    required this.rxEstado,
    required this.estadoItems,
    required this.onEstado,
    required this.rxTipo,
    required this.onTipo,
    required this.rxCt,
    required this.ctItems,
    required this.ctLabel,
    required this.onCt,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: FilterChipDropdown<EstadoActividad>(
                icon: Icons.flag_outlined,
                groupColor: kEstadoFilterGroupColor,
                rxValue: rxEstado,
                items: estadoItems,
                itemLabel: (e) => e.etiqueta,
                itemColor: (e) =>
                    kEstadoFilterColors[e] ?? kEstadoFilterGroupColor,
                onChanged: onEstado,
                allLabel: 'Estado',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FilterChipDropdown<TipoActividad>(
                icon: Icons.construction_outlined,
                groupColor: kTipoFilterGroupColor,
                rxValue: rxTipo,
                items: TipoActividad.values,
                itemLabel: (t) => t.etiqueta,
                itemColor: (t) => kTipoFilterColors[t] ?? kTipoFilterGroupColor,
                onChanged: onTipo,
                allLabel: 'Tipo',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FilterChipDropdown<String>(
                icon: Icons.business_outlined,
                groupColor: kCtFilterGroupColor,
                rxValue: rxCt,
                items: ctItems,
                itemLabel: ctLabel,
                itemColor: (_) => kCtFilterGroupColor,
                onChanged: onCt,
                allLabel: 'CT',
                emptyLabel: 'CT',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
