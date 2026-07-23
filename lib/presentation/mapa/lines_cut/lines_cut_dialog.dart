import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/app_theme.dart';
import '../../../domain/entities/segmento_entity.dart';

/// Resultado del diálogo de captura tras aplicar un corte.
class CutDialogResult {
  const CutDialogResult({
    required this.descripcion,
    required this.tipoActividad,
    required this.estado,
  });

  final String descripcion;
  final TipoActividad tipoActividad;
  final EstadoActividad estado;
}

/// Abre un modal con los campos mínimos (descripción / tipo) que se aplicarán
/// a todos los segmentos extraídos del corte. El estado es siempre
/// [EstadoActividad.contratista] para los segmentos creados desde la app.
/// Devuelve `null` si el usuario cancela.
Future<CutDialogResult?> showLinesCutCaptureDialog({
  required String headerTitle,
  required String headerSubtitle,
  required double totalMeters,
  required double totalSquareMeters,
  String initialDescripcion = '',
  TipoActividad initialTipoActividad = TipoActividad.posicionDesherbajeTraza,
}) {
  return Get.dialog<CutDialogResult>(
    _LinesCutCaptureDialog(
      headerTitle: headerTitle,
      headerSubtitle: headerSubtitle,
      totalMeters: totalMeters,
      totalSquareMeters: totalSquareMeters,
      initialDescripcion: initialDescripcion,
      initialTipoActividad: initialTipoActividad,
    ),
    barrierDismissible: false,
  );
}

/// StatefulWidget so the `TextEditingController` is disposed by the framework
/// when the route is actually gone. Creating it in [showLinesCutCaptureDialog]
/// and disposing it when `Get.dialog`'s future resolves is too early: the
/// dialog is still animating out and its `TextField` keeps rebuilding.
class _LinesCutCaptureDialog extends StatefulWidget {
  const _LinesCutCaptureDialog({
    required this.headerTitle,
    required this.headerSubtitle,
    required this.totalMeters,
    required this.totalSquareMeters,
    required this.initialDescripcion,
    required this.initialTipoActividad,
  });

  final String headerTitle;
  final String headerSubtitle;
  final double totalMeters;
  final double totalSquareMeters;
  final String initialDescripcion;
  final TipoActividad initialTipoActividad;

  @override
  State<_LinesCutCaptureDialog> createState() => _LinesCutCaptureDialogState();
}

class _LinesCutCaptureDialogState extends State<_LinesCutCaptureDialog> {
  late final TextEditingController _descripcionCtrl =
      TextEditingController(text: widget.initialDescripcion);
  late TipoActividad _tipo = widget.initialTipoActividad;

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.moduleGreen,
                    child:
                        Icon(Icons.content_cut, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.headerTitle, style: AppTextStyles.title),
                        if (widget.headerSubtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(widget.headerSubtitle,
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.textSecondary)),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          widget.totalMeters >= 1000
                              ? '${(widget.totalMeters / 1000).toStringAsFixed(2)} km totales'
                              : '${widget.totalMeters.toStringAsFixed(0)} m totales',
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.moduleGreenDark,
                              fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${widget.totalSquareMeters.toStringAsFixed(0)} m² de superficie',
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.moduleGreenDark,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              // El campo absorbe el alto sobrante en lugar de fijar un número de
              // líneas: con `minLines: 10` el diálogo desbordaba en móvil y
              // volvía a desbordar al crecer el texto.
              Expanded(
                child: TextField(
                  controller: _descripcionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    prefixIcon: Icon(Icons.description_outlined),
                    alignLabelWithHint: true,
                  ),
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<TipoActividad>(
                initialValue: _tipo,
                // Sin isExpanded el botón se dimensiona al texto natural y la
                // etiqueta más larga desborda la fila interna (RenderFlex).
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Tipo de actividad',
                  prefixIcon: Icon(Icons.construction_outlined),
                ),
                items: TipoActividad.values
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child:
                              Text(t.etiqueta, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _tipo = v);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Get.back(result: null),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Aplicar'),
                    onPressed: () => Get.back(
                      result: CutDialogResult(
                        descripcion: _descripcionCtrl.text.trim(),
                        tipoActividad: _tipo,
                        estado: EstadoActividad.contratista,
                      ),
                    ),
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
