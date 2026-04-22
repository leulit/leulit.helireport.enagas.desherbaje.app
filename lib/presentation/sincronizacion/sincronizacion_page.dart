import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/app_theme.dart';
import 'sincronizacion_controller.dart';

class SincronizacionPage extends GetView<SincronizacionController> {
  const SincronizacionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.moduleGreenLight,
      appBar: AppBar(
        title: const Text('Sincronización'),
        leading: Obx(() => IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: controller.isRunning.value ? null : controller.volver,
            )),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              _HeaderCard(),
              SizedBox(height: AppSpacing.lg),
              _ProgressSection(),
              SizedBox(height: AppSpacing.lg),
              Expanded(child: _EntidadesList()),
              SizedBox(height: AppSpacing.lg),
              _Acciones(),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends GetView<SincronizacionController> {
  const _HeaderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.moduleGreen,
            child: Icon(Icons.cloud_sync, color: Colors.white, size: 28),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sincronización de datos', style: AppTextStyles.title),
                const SizedBox(height: AppSpacing.xs),
                Obx(() => Text(
                      controller.pasoActual.value.isEmpty
                          ? 'Pulsa iniciar para descargar los datos del servidor y subir los pendientes del dispositivo.'
                          : controller.pasoActual.value,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressSection extends GetView<SincronizacionController> {
  const _ProgressSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Progreso global', style: AppTextStyles.subtitle),
              Obx(() => Text(
                    '${(controller.progresoGlobal.value * 100).toStringAsFixed(0)} %',
                    style: AppTextStyles.metric
                        .copyWith(color: AppColors.moduleGreenDark),
                  )),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Obx(() => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: controller.progresoGlobal.value,
                  minHeight: 10,
                  backgroundColor: AppColors.moduleGreenLight,
                  valueColor: const AlwaysStoppedAnimation(AppColors.moduleGreen),
                ),
              )),
          Obx(() {
            final err = controller.error.value;
            if (err == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      err,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _EntidadesList extends GetView<SincronizacionController> {
  const _EntidadesList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Obx(() => ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: controller.entidades.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.divider),
            itemBuilder: (_, i) => _EntidadTile(entidad: controller.entidades[i]),
          )),
    );
  }
}

class _EntidadTile extends StatelessWidget {
  const _EntidadTile({required this.entidad});

  final SyncEntidad entidad;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final estado = entidad.estado.value;
      final procesados = entidad.procesados.value;
      final total = entidad.total.value;
      final msgError = entidad.mensajeError.value;

      return ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.moduleGreenLight,
          child: Icon(entidad.icono,
              color: AppColors.moduleGreenDark, size: 20),
        ),
        title: Text(entidad.titulo, style: AppTextStyles.subtitle),
        subtitle: Text(
          _subtitulo(estado, procesados, total, msgError),
          style: AppTextStyles.caption.copyWith(
            color: estado == SyncEstado.error
                ? Colors.red
                : AppColors.textSecondary,
          ),
        ),
        trailing: _EstadoTrailing(estado: estado),
      );
    });
  }

  String _subtitulo(SyncEstado e, int procesados, int total, String? err) {
    if (e == SyncEstado.error && err != null) return err;
    if (total == 0) return _estadoTexto(e);
    return '$procesados / $total · ${_estadoTexto(e)}';
  }

  String _estadoTexto(SyncEstado e) => switch (e) {
        SyncEstado.pendiente => 'Pendiente',
        SyncEstado.enProceso => 'En proceso…',
        SyncEstado.completado => 'Completado',
        SyncEstado.error => 'Error',
      };
}

class _EstadoTrailing extends StatelessWidget {
  const _EstadoTrailing({required this.estado});

  final SyncEstado estado;

  @override
  Widget build(BuildContext context) {
    return switch (estado) {
      SyncEstado.pendiente => const Icon(
          Icons.schedule,
          color: AppColors.textSecondary,
        ),
      SyncEstado.enProceso => const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.moduleGreen,
          ),
        ),
      SyncEstado.completado => const Icon(
          Icons.check_circle,
          color: AppColors.moduleGreen,
        ),
      SyncEstado.error => const Icon(
          Icons.error_outline,
          color: Colors.red,
        ),
    };
  }
}

class _Acciones extends GetView<SincronizacionController> {
  const _Acciones();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isCompleted.value) {
        return SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Finalizar'),
            onPressed: controller.finalizar,
          ),
        );
      }

      if (controller.isRunning.value) {
        return SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Cancelar'),
            onPressed: controller.cancelar,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        );
      }

      final hayError = controller.error.value != null;
      return SizedBox(
        height: 52,
        child: ElevatedButton.icon(
          icon: Icon(hayError ? Icons.refresh : Icons.play_arrow),
          label: Text(hayError ? 'Reintentar' : 'Iniciar sincronización'),
          onPressed: hayError ? controller.reintentar : controller.iniciar,
        ),
      );
    });
  }
}
