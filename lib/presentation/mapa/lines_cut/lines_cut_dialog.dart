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
  final descripcionCtrl = TextEditingController(text: initialDescripcion);
  final tipoRx = initialTipoActividad.obs;

  final result = Get.dialog<CutDialogResult>(
    Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                    child: Icon(Icons.content_cut,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(headerTitle, style: AppTextStyles.title),
                        if (headerSubtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(headerSubtitle,
                              style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textSecondary)),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          totalMeters >= 1000
                              ? '${(totalMeters / 1000).toStringAsFixed(2)} km totales'
                              : '${totalMeters.toStringAsFixed(0)} m totales',
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.moduleGreenDark,
                              fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${totalSquareMeters.toStringAsFixed(0)} m² de superficie',
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
              TextField(
                controller: descripcionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  prefixIcon: Icon(Icons.description_outlined),
                  alignLabelWithHint: true,
                ),
                minLines: 10,
                maxLines: 14,
                textAlignVertical: TextAlignVertical.top,
              ),
              const SizedBox(height: AppSpacing.md),
              Obx(() => DropdownButtonFormField<TipoActividad>(
                    initialValue: tipoRx.value,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de actividad',
                      prefixIcon: Icon(Icons.construction_outlined),
                    ),
                    items: TipoActividad.values
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t.etiqueta),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) tipoRx.value = v;
                    },
                  )),
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
                        descripcion: descripcionCtrl.text.trim(),
                        tipoActividad: tipoRx.value,
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
    ),
    barrierDismissible: false,
  );

  return result;
}
