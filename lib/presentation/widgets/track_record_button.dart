import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';

import '../../core/app_theme.dart';
import '../../core/services/gps_background_service.dart';
import '../../data/repository/auth_repository_impl.dart';
import 'finalize_traza_dialog.dart';

/// AppBar action that starts/stops the manual GPS track ("traza") recording.
///
/// Reflects [GpsBackgroundService.state] via [ValueListenableBuilder], so it
/// stays in sync no matter which screen mounts it — recording is not tied to
/// any single page and survives navigation between them.
class TrackRecordButton extends StatelessWidget {
  const TrackRecordButton({super.key});

  GpsBackgroundService get _service => DI.get<GpsBackgroundService>();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GpsTrackingState>(
      valueListenable: _service.state,
      builder: (context, state, _) {
        final running = state == GpsTrackingState.running;
        return IconButton(
          icon: Icon(
            running ? Icons.stop_circle : Icons.fiber_manual_record,
            // Rojo en marcha: debe leerse como "grabando" de un vistazo,
            // distinto del resto de acciones verdes de la AppBar.
            color: running ? const Color(0xFFC62828) : AppColors.moduleGreen,
          ),
          tooltip: running
              ? 'Finalizar registro de traza'
              : 'Iniciar registro de traza',
          onPressed: () => running ? _finalizar() : _iniciar(context),
        );
      },
    );
  }

  Future<void> _iniciar(BuildContext context) async {
    final ok = await _service.start();
    if (ok || !context.mounted) return;

    final permission = await Geolocator.checkPermission();
    final permanentlyDenied = permission == LocationPermission.deniedForever;
    if (!context.mounted) return;

    final reason =
        _service.lastError.value ?? 'No se pudo iniciar el registro.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(reason),
        action: permanentlyDenied
            ? SnackBarAction(
                label: 'Ajustes',
                onPressed: Geolocator.openAppSettings,
              )
            : null,
      ),
    );
  }

  Future<void> _finalizar() async {
    var initialName =
        'Traza ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}';
    final user = await AuthRepositoryImpl().getCurrentUser();
    if (user != null) {
      final open = await _service.openTrazaFor(user.id);
      if (open != null) initialName = open.name;
    }

    final name = await showFinalizeTrazaDialog(initialName: initialName);
    await _service.finish(name: name);
  }
}
