import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'sincronizacion_controller.dart';
import 'sync_models.dart';

class SincronizacionPage extends GetView<SincronizacionController> {
  const SincronizacionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincronización'),
        leading: Obx(() => IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: controller.isWorking.value ? null : controller.volver,
            )),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            _StatusHeader(),
            Expanded(child: _MasterDataSection()),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────── Header ──────────────────────────────────────

class _StatusHeader extends GetView<SincronizacionController> {
  const _StatusHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Obx(() => Icon(
                controller.isOnline.value
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                color: controller.isOnline.value
                    ? Colors.green.shade700
                    : Colors.orange.shade700,
              )),
          const SizedBox(width: 8),
          Obx(() => Text(
                controller.isOnline.value ? 'Online' : 'Sin conexión',
                style: Theme.of(context).textTheme.bodyMedium,
              )),
          const Spacer(),
          Obx(() {
            if (!controller.isWorking.value) return const SizedBox.shrink();
            return Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: controller.cancelar,
                  child: const Text('Cancelar'),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────── Datos maestros ──────────────────────────────────

class _MasterDataSection extends GetView<SincronizacionController> {
  const _MasterDataSection();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_download_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Datos maestros',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Obx(() => FilledButton.icon(
                          onPressed: (controller.isWorking.value ||
                                  !controller.isOnline.value)
                              ? null
                              : controller.descargarTodo,
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Descargar todo'),
                        )),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Descarga la información necesaria para trabajar offline. '
                  'Requiere conexión a internet.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Obx(() => Column(
                      children: controller.rows
                          .map((r) => _MasterDataRowTile(row: r))
                          .toList(),
                    )),
                Obx(() {
                  final err = controller.lastError.value;
                  if (err == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      err,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MasterDataRowTile extends GetView<SincronizacionController> {
  final MasterDataRow row;
  const _MasterDataRowTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final disabled = row.status == MasterDataStatus.unavailable;
    final last = row.lastDownloadAt;
    final isDownloading = row.status == MasterDataStatus.downloading;
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: _statusIcon(),
          title: Text(
            row.kind.title,
            style: disabled
                ? TextStyle(color: Colors.grey.shade600)
                : null,
          ),
          subtitle: Text(
            _subtitle(last),
            style: _subtitleStyle(context),
          ),
          trailing: disabled
              ? Text(
                  'No disponible',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : Obx(() => FilledButton.tonal(
                    onPressed: (controller.isWorking.value ||
                            !controller.isOnline.value)
                        ? null
                        : () => controller.descargar(row.kind),
                    child: const Text('Descargar'),
                  )),
        ),
        if (isDownloading)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(
              value: row.progress,
              color: primary,
              backgroundColor: primary.withValues(alpha: 0.15),
              minHeight: 6,
            ),
          ),
      ],
    );
  }

  Widget _statusIcon() {
    switch (row.status) {
      case MasterDataStatus.downloading:
        return SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: row.progress,
          ),
        );
      case MasterDataStatus.success:
        return Icon(Icons.check_circle, color: Colors.green.shade700);
      case MasterDataStatus.error:
        return Icon(Icons.error_outline, color: Colors.red.shade700);
      case MasterDataStatus.unavailable:
        return Icon(Icons.cloud_off_outlined, color: Colors.grey.shade500);
      case MasterDataStatus.idle:
        return const Icon(Icons.cloud_outlined);
    }
  }

  String _subtitle(DateTime? last) {
    if (row.status == MasterDataStatus.downloading) {
      final label = row.progressLabel;
      if (label != null) {
        return '${row.kind.description}\nDescargando $label archivos…';
      }
      return '${row.kind.description}\nDescargando…';
    }
    if (row.status == MasterDataStatus.error && row.errorMessage != null) {
      return row.errorMessage!;
    }
    if (row.status == MasterDataStatus.unavailable) {
      return row.kind.description;
    }
    if (last == null) return '${row.kind.description}\nNunca descargado';
    return '${row.kind.description}\nÚltima descarga: ${_relativeTime(last)}';
  }

  TextStyle? _subtitleStyle(BuildContext context) {
    if (row.status == MasterDataStatus.error) {
      return TextStyle(color: Colors.red.shade700);
    }
    if (row.status == MasterDataStatus.downloading) {
      return TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      );
    }
    return null;
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'hace unos segundos';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return DateFormat('d MMM HH:mm', 'es').format(t);
  }
}
