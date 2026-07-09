import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/app_theme.dart';
import 'sincronizacion_controller.dart';
import 'sync_models.dart';

/// Página de sincronización — descarga de datos maestros.
///
/// Rediseño (jul 2026): adopta el lenguaje visual del módulo (`AppColors` /
/// `AppTextStyles` / `AppSpacing`, AppBar verde con subrayado) e introduce una
/// tarjeta-resumen "listo para campo". La lógica del controller no cambia: se
/// reutilizan `isOnline`, `isWorking`, `lastError`, `rows`, `descargarTodo`,
/// `descargar`, `cancelar` y `volver` tal cual. El estado de preparación es
/// presentacional y se deriva aquí de `rows` (sin tocar el controller).
class SincronizacionPage extends GetView<SincronizacionController> {
  const SincronizacionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.moduleGreenLight,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(2),
          child: SizedBox(
            height: 2,
            child: ColoredBox(color: Color(0xFFA5D6A7)),
          ),
        ),
        leading: Obx(() => IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.moduleGreen),
              tooltip: 'Volver',
              onPressed: controller.isWorking.value ? null : controller.volver,
            )),
        title: const Text(
          'Sincronización',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.moduleGreenText,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: const [
            _HeroCard(),
            SizedBox(height: AppSpacing.lg),
            _ItemsSurface(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────── Tarjeta-resumen "listo para campo" ──────────────────

class _HeroCard extends GetView<SincronizacionController> {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final rows = controller.rows;
      final online = controller.isOnline.value;
      final working = controller.isWorking.value;
      final error = controller.lastError.value;
      final r = _readiness(rows);
      final loading = r.total == 0;
      final pending = (r.total - r.done).clamp(0, r.total);
      final allDone = !loading && pending == 0;

      final _HeroStatus st = loading
          ? const _HeroStatus(
              icon: Icons.hourglass_empty,
              color: AppColors.textSecondary,
              headline: 'Cargando…',
            )
          : !allDone && !online
              ? _HeroStatus(
                  icon: Icons.cloud_off_outlined,
                  color: Colors.orange.shade900,
                  headline:
                      'Sin conexión — $pending ${pending == 1 ? 'pendiente' : 'pendientes'}',
                )
              : allDone
                  ? const _HeroStatus(
                      icon: Icons.check_circle,
                      color: AppColors.moduleGreen,
                      headline: 'Listo para trabajar en campo',
                    )
                  : _HeroStatus(
                      icon: Icons.cloud_download_outlined,
                      color: const Color(0xFFE65100),
                      headline:
                          'Faltan $pending ${pending == 1 ? 'descarga' : 'descargas'}',
                    );

      return Card(
        elevation: 1,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: st.color.withValues(alpha: 0.25)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _ConnectivityChip(online: online),
                  const Spacer(),
                  Text(
                    loading ? '…' : '${r.done} de ${r.total} al día',
                    style: AppTextStyles.metric.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _SegmentedProgress(rows: rows),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Icon(st.icon, color: st.color, size: 26),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      st.headline,
                      style: AppTextStyles.title.copyWith(color: st.color),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (working)
                _WorkingBar(onCancel: controller.cancelar)
              else
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: (online && !loading)
                        ? controller.descargarTodo
                        : null,
                    icon: const Icon(Icons.download, size: 20),
                    label: Text(
                      allDone ? 'Actualizar todo' : 'Descargar todo',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.md),
                _ErrorBanner(message: error),
              ],
            ],
          ),
        ),
      );
    });
  }
}

class _HeroStatus {
  final IconData icon;
  final Color color;
  final String headline;
  const _HeroStatus({
    required this.icon,
    required this.color,
    required this.headline,
  });
}

class _ConnectivityChip extends StatelessWidget {
  final bool online;
  const _ConnectivityChip({required this.online});

  @override
  Widget build(BuildContext context) {
    final color = online ? AppColors.moduleGreen : Colors.orange.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            online ? 'Online' : 'Sin conexión',
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Una pastilla por fila disponible, coloreada según su estado. Da una lectura
/// de un vistazo del progreso global.
class _SegmentedProgress extends StatelessWidget {
  final List<MasterDataRow> rows;
  const _SegmentedProgress({required this.rows});

  @override
  Widget build(BuildContext context) {
    final available = rows
        .where((r) => r.status != MasterDataStatus.unavailable)
        .toList();
    if (available.isEmpty) {
      return const SizedBox(height: 8);
    }
    final done = available
        .where((r) =>
            r.status == MasterDataStatus.success ||
            (r.status == MasterDataStatus.idle && r.lastDownloadAt != null))
        .length;
    final errors =
        available.where((r) => r.status == MasterDataStatus.error).length;
    final label = '$done de ${available.length} al día'
        '${errors > 0 ? ', $errors con error' : ''}';
    return Semantics(
      container: true,
      label: label,
      child: Row(
        children: [
          for (var i = 0; i < available.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: _pillColor(available[i]),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Color _pillColor(MasterDataRow r) {
    switch (r.status) {
      case MasterDataStatus.error:
        return Colors.red.shade600;
      case MasterDataStatus.downloading:
        return AppColors.moduleGreen.withValues(alpha: 0.5);
      case MasterDataStatus.success:
        return AppColors.moduleGreen;
      case MasterDataStatus.idle:
        return r.lastDownloadAt != null
            ? AppColors.moduleGreen
            : const Color(0xFFE0E0E0);
      case MasterDataStatus.unavailable:
        return const Color(0xFFE0E0E0);
    }
  }
}

class _WorkingBar extends StatelessWidget {
  final VoidCallback onCancel;
  const _WorkingBar({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: LinearProgressIndicator(
            minHeight: 6,
            color: AppColors.moduleGreen,
            backgroundColor: Color(0x22388E3C),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        TextButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.close, size: 18),
          label: const Text('Cancelar'),
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: Colors.red.shade700),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: AppTextStyles.caption
                      .copyWith(color: Colors.red.shade700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pulsa «Descargar todo» para reintentar.',
                  style: AppTextStyles.metricSmall
                      .copyWith(color: Colors.red.shade400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso no bloqueante (ámbar) para una fila `success` con cambios locales
/// pendientes de subir.
class _WarningBanner extends StatelessWidget {
  final String message;
  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 16, color: Colors.orange.shade800),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style:
                  AppTextStyles.caption.copyWith(color: Colors.orange.shade800),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────── Lista de ítems ──────────────────────────────

class _ItemsSurface extends GetView<SincronizacionController> {
  const _ItemsSurface();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Obx(() {
        final rows = controller.rows.toList();
        if (rows.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.moduleGreen),
              ),
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
              _ItemTile(row: rows[i]),
            ],
          ],
        );
      }),
    );
  }
}

class _ItemTile extends GetView<SincronizacionController> {
  final MasterDataRow row;
  const _ItemTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final disabled = row.status == MasterDataStatus.unavailable;
    final downloading = row.status == MasterDataStatus.downloading;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _StatusIcon(row: row),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.kind.title,
                      style: AppTextStyles.subtitle.copyWith(
                        color: disabled
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _metaLine(),
                      style: AppTextStyles.caption.copyWith(color: _metaColor()),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      row.kind.description,
                      style: AppTextStyles.metricSmall.copyWith(
                        color: AppColors.textSecondary.withValues(alpha: 0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _TrailingAction(row: row),
            ],
          ),
          if (row.warningMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _WarningBanner(message: row.warningMessage!),
          ],
          if (downloading) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              label: 'Descargando ${row.kind.title}',
              value: row.progressLabel,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: row.progress,
                  minHeight: 5,
                  color: AppColors.moduleGreen,
                  backgroundColor: const Color(0x22388E3C),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _metaLine() {
    switch (row.status) {
      case MasterDataStatus.downloading:
        return row.progressLabel ?? 'Descargando…';
      case MasterDataStatus.error:
        return row.errorMessage ?? 'Error en la descarga';
      case MasterDataStatus.unavailable:
        return 'No disponible';
      case MasterDataStatus.success:
      case MasterDataStatus.idle:
        final last = row.lastDownloadAt;
        if (last == null) return 'Nunca descargado';
        final cache = row.servedFromCache ? ' · desde caché' : '';
        return 'Última descarga: ${_relativeTime(last)}$cache';
    }
  }

  Color _metaColor() {
    switch (row.status) {
      case MasterDataStatus.error:
        return Colors.red.shade700;
      case MasterDataStatus.downloading:
        return AppColors.moduleGreen;
      default:
        return AppColors.textSecondary;
    }
  }
}

class _StatusIcon extends StatelessWidget {
  final MasterDataRow row;
  const _StatusIcon({required this.row});

  @override
  Widget build(BuildContext context) {
    switch (row.status) {
      case MasterDataStatus.downloading:
        return SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: row.progress,
            color: AppColors.moduleGreen,
          ),
        );
      case MasterDataStatus.success:
        return const Icon(Icons.check_circle, color: AppColors.moduleGreen);
      case MasterDataStatus.error:
        return Icon(Icons.error, color: Colors.red.shade600);
      case MasterDataStatus.unavailable:
        return Icon(Icons.cloud_off_outlined, color: Colors.grey.shade400);
      case MasterDataStatus.idle:
        return row.lastDownloadAt != null
            ? Icon(Icons.check_circle_outline,
                color: AppColors.moduleGreen.withValues(alpha: 0.7))
            : Icon(Icons.radio_button_unchecked, color: Colors.grey.shade400);
    }
  }
}

class _TrailingAction extends GetView<SincronizacionController> {
  final MasterDataRow row;
  const _TrailingAction({required this.row});

  @override
  Widget build(BuildContext context) {
    if (row.status == MasterDataStatus.unavailable) {
      return Text(
        'No disponible',
        style: AppTextStyles.metricSmall.copyWith(color: Colors.grey.shade500),
      );
    }
    if (row.status == MasterDataStatus.downloading) {
      // El spinner de estado ya comunica el progreso; sin acción por fila.
      return const SizedBox(width: 48);
    }

    final hasData = row.status == MasterDataStatus.success ||
        row.lastDownloadAt != null;
    final isError = row.status == MasterDataStatus.error;
    final icon = (hasData && !isError) ? Icons.refresh : Icons.download;
    final tooltip = (hasData && !isError) ? 'Re-descargar' : 'Descargar';

    return Obx(() {
      final enabled =
          !controller.isWorking.value && controller.isOnline.value;
      return IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        color: AppColors.moduleGreen,
        onPressed: enabled ? () => controller.descargar(row.kind) : null,
      );
    });
  }
}

// ─────────────────────────────── Helpers ────────────────────────────────────

typedef _Readiness = ({int done, int total});

_Readiness _readiness(List<MasterDataRow> rows) {
  final available =
      rows.where((r) => r.status != MasterDataStatus.unavailable);
  final total = available.length;
  final done = available
      .where((r) =>
          r.status == MasterDataStatus.success ||
          (r.status == MasterDataStatus.idle && r.lastDownloadAt != null))
      .length;
  return (done: done, total: total);
}

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'hace unos segundos';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  return DateFormat('d MMM HH:mm', 'es').format(t);
}
