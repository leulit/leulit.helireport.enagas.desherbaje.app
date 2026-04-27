import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/sync/sync.dart';
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
        actions: [
          Obx(() => IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refrescar',
                onPressed:
                    controller.isWorking.value ? null : controller.refreshAll,
              )),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _StatusHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  _PrepareFieldWorkCard(),
                  SizedBox(height: 16),
                  _PendingUploadsSection(),
                  SizedBox(height: 16),
                  _DownloadablesSection(),
                  SizedBox(height: 16),
                  _ConflictsSection(),
                  SizedBox(height: 24),
                ],
              ),
            ),
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
                Text(
                  controller.currentStep.value,
                  style: Theme.of(context).textTheme.bodySmall,
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

// ─────────────────────────── Preparar trabajo de campo ───────────────────────

class _PrepareFieldWorkCard extends GetView<SincronizacionController> {
  const _PrepareFieldWorkCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.outdoor_grill_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Preparar trabajo de campo',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Sube todo lo pendiente y descarga los datos maestros antes de '
              'salir a campo. Solo necesita conexión a internet ahora.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Obx(() => FilledButton.icon(
                  onPressed: (controller.isWorking.value ||
                          !controller.isOnline.value)
                      ? null
                      : controller.prepararTrabajoCampo,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Preparar ahora'),
                )),
            Obx(() {
              final report = controller.lastReport.value;
              if (report == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _ReadinessSummary(report: report),
              );
            }),
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
    );
  }
}

class _ReadinessSummary extends StatelessWidget {
  final FieldReadinessReport report;
  const _ReadinessSummary({required this.report});

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];
    if (report.cancelled) {
      lines.add(const Text('Cancelado por el usuario.'));
    } else if (report.authExpired) {
      lines.add(Text(
        'Sesión expirada — vuelve a iniciar sesión.',
        style: TextStyle(color: Colors.red.shade700),
      ));
    } else {
      lines.add(Text('✓ ${report.pendingPushed} subidos'));
      if (report.pendingFailed > 0) {
        lines.add(Text(
          '✗ ${report.pendingFailed} con problemas',
          style: TextStyle(color: Colors.orange.shade800),
        ));
      }
      lines.add(Text('↓ ${report.pulledOk} descargados'));
      if (report.conflictsFound > 0) {
        lines.add(Text(
          '⚠ ${report.conflictsFound} conflictos por revisar',
          style: TextStyle(color: Colors.orange.shade800),
        ));
      }
      for (final e in report.errors) {
        lines.add(Text(e, style: TextStyle(color: Colors.red.shade700)));
      }
      if (report.isReadyForField) {
        lines.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Listo para salir a campo.',
            style: TextStyle(
              color: Colors.green.shade800,
              fontWeight: FontWeight.bold,
            ),
          ),
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }
}

// ─────────────────────────── Pendientes de subir ─────────────────────────────

class _PendingUploadsSection extends GetView<SincronizacionController> {
  const _PendingUploadsSection();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Pendientes de subir',
      icon: Icons.upload,
      trailing: Obx(() => TextButton.icon(
            onPressed: controller.isWorking.value ? null : controller.subirTodo,
            icon: const Icon(Icons.cloud_upload_outlined, size: 18),
            label: const Text('Subir todo'),
          )),
      child: Column(
        children: [
          Obx(() => controller.pendingByEntity.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Sin entidades registradas.'),
                )
              : Column(
                  children: controller.pendingByEntity
                      .map((e) => _PendingEntityRow(entity: e))
                      .toList(),
                )),
          Obx(() {
            if (controller.rejectedJobs.isEmpty) return const SizedBox.shrink();
            return _RejectedJobsExpansion(jobs: controller.rejectedJobs);
          }),
        ],
      ),
    );
  }
}

class _PendingEntityRow extends GetView<SincronizacionController> {
  final PendingByEntity entity;
  const _PendingEntityRow({required this.entity});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(entity.entityType),
      subtitle: Text(
        entity.hasAnything
            ? '${entity.pending} pendientes${entity.rejected > 0 ? ' • ${entity.rejected} rechazadas' : ''}'
            : 'Sin pendientes',
      ),
      trailing: entity.pending > 0
          ? FilledButton.tonal(
              onPressed: controller.isWorking.value
                  ? null
                  : () => controller.subirEntidad(entity.entityType),
              child: const Text('Subir'),
            )
          : null,
    );
  }
}

class _RejectedJobsExpansion extends StatelessWidget {
  final List<SyncJob> jobs;
  const _RejectedJobsExpansion({required this.jobs});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        'Subidas rechazadas (${jobs.length})',
        style: TextStyle(color: Colors.red.shade700),
      ),
      children: jobs.map((j) => _RejectedJobRow(job: j)).toList(),
    );
  }
}

class _RejectedJobRow extends GetView<SincronizacionController> {
  final SyncJob job;
  const _RejectedJobRow({required this.job});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${job.entityType} • ${job.operation.name}'),
      subtitle: Text(
        job.lastError ?? 'Rechazado por el servidor.',
        style: TextStyle(color: Colors.red.shade700),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reintentar',
            onPressed: () => controller.reintentarRechazado(job.id),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Descartar',
            onPressed: () => _confirmDiscard(context, job.id),
          ),
        ],
      ),
    );
  }

  void _confirmDiscard(BuildContext context, int jobId) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar trabajo'),
        content: const Text(
          'Si descartas este trabajo, se perderá el cambio asociado. '
          '¿Quieres continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.descartarRechazado(jobId);
            },
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Datos descargables ──────────────────────────────

class _DownloadablesSection extends GetView<SincronizacionController> {
  const _DownloadablesSection();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Datos descargables',
      icon: Icons.download,
      child: Obx(() {
        if (controller.downloadable.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'No hay entidades pulleables registradas.',
            ),
          );
        }
        return Column(
          children: controller.downloadable
              .map((d) => _DownloadableRow(entity: d))
              .toList(),
        );
      }),
    );
  }
}

class _DownloadableRow extends GetView<SincronizacionController> {
  final DownloadableEntity entity;
  const _DownloadableRow({required this.entity});

  @override
  Widget build(BuildContext context) {
    final last = entity.lastPulledAt;
    final lastText = last == null
        ? 'Nunca descargado'
        : 'Última descarga: ${_relativeTime(last)}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(entity.entityType),
      subtitle: Text(lastText),
      trailing: Obx(() => FilledButton.tonal(
            onPressed: (controller.isWorking.value ||
                    !controller.isOnline.value)
                ? null
                : () => controller.descargarEntidad(entity.entityType),
            child: const Text('Descargar'),
          )),
    );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'hace unos segundos';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return DateFormat('d MMM HH:mm', 'es').format(t);
  }
}

// ─────────────────────────── Conflictos de descarga ──────────────────────────

class _ConflictsSection extends GetView<SincronizacionController> {
  const _ConflictsSection();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Conflictos de descarga',
      icon: Icons.warning_amber_outlined,
      iconColor: Colors.orange.shade700,
      child: Obx(() {
        if (controller.conflicts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Text('No hay conflictos por revisar.'),
          );
        }
        return Column(
          children: controller.conflicts
              .map((c) => _ConflictRowWidget(conflict: c))
              .toList(),
        );
      }),
    );
  }
}

class _ConflictRowWidget extends GetView<SincronizacionController> {
  final ConflictRow conflict;
  const _ConflictRowWidget({required this.conflict});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.compare_arrows),
      title: Text('${conflict.entityType} • ${conflict.clientId.substring(0, 8)}…'),
      subtitle: Text(
        'Detectado ${DateFormat('d MMM HH:mm', 'es').format(conflict.detectedAt)}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showDiffDialog(context),
    );
  }

  Future<void> _showDiffDialog(BuildContext context) async {
    final fmt = controller.formatConflict(conflict);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Diferencias detectadas'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(children: [
                  SizedBox(width: 100, child: Text('Campo',
                      style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(child: Text('Local',
                      style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(child: Text('Servidor',
                      style: TextStyle(fontWeight: FontWeight.bold))),
                ]),
                const Divider(),
                ..._buildDiffRows(fmt),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.resolverConflicto(
                conflict: conflict,
                choice: ConflictResolutionChoice.keepLocal,
              );
            },
            child: const Text('Conservar local'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.resolverConflicto(
                conflict: conflict,
                choice: ConflictResolutionChoice.keepServer,
              );
            },
            child: const Text('Sobreescribir con servidor'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDiffRows(
    ({
      Map<String, String> local,
      Map<String, String> remote,
      Set<String> diffKeys,
    }) fmt,
  ) {
    final keys = <String>{...fmt.local.keys, ...fmt.remote.keys}.toList();
    return keys.map((k) {
      final l = fmt.local[k] ?? '—';
      final r = fmt.remote[k] ?? '—';
      final differs = fmt.diffKeys.contains(k);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: Text(k)),
            Expanded(
              child: Text(
                l,
                style: differs
                    ? TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
                      )
                    : null,
              ),
            ),
            Expanded(
              child: Text(
                r,
                style: differs
                    ? TextStyle(
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.bold,
                      )
                    : null,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

// ─────────────────────────────── Helpers ─────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final Widget? trailing;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.iconColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
