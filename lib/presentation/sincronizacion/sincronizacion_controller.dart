import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/app_router.dart';

enum SyncEstado { pendiente, enProceso, completado, error }

class SyncEntidad {
  SyncEntidad({
    required this.id,
    required this.titulo,
    required this.icono,
    int total = 0,
    int procesados = 0,
    SyncEstado estado = SyncEstado.pendiente,
    String? mensajeError,
  })  : total = total.obs,
        procesados = procesados.obs,
        estado = estado.obs,
        mensajeError = Rx<String?>(mensajeError);

  final String id;
  final String titulo;
  final IconData icono;
  final RxInt total;
  final RxInt procesados;
  final Rx<SyncEstado> estado;
  final Rx<String?> mensajeError;

  double get progreso {
    final t = total.value;
    if (t == 0) return 0;
    return (procesados.value / t).clamp(0.0, 1.0);
  }
}

class SincronizacionController extends GetxController {
  final isRunning = false.obs;
  final isCompleted = false.obs;
  final progresoGlobal = 0.0.obs;
  final pasoActual = ''.obs;
  final error = Rx<String?>(null);

  late final RxList<SyncEntidad> entidades = <SyncEntidad>[
    SyncEntidad(
      id: 'usuarios',
      titulo: 'Usuarios',
      icono: Icons.people_outline,
    ),
    SyncEntidad(
      id: 'cts',
      titulo: 'Centros de Trabajo (CT)',
      icono: Icons.apartment_outlined,
    ),
    SyncEntidad(
      id: 'segmentos',
      titulo: 'Segmentos y actividades',
      icono: Icons.timeline,
    ),
    SyncEntidad(
      id: 'catalogos',
      titulo: 'Catálogos y maestros',
      icono: Icons.folder_special_outlined,
    ),
  ].obs;

  /// Lanza el proceso completo de sincronización.
  Future<void> iniciar() async {
    // Pendiente de implementación
  }

  /// Detiene la sincronización en curso.
  Future<void> cancelar() async {
    // Pendiente de implementación
  }

  /// Reanuda tras un error, reintentando las entidades fallidas.
  Future<void> reintentar() async {
    // Pendiente de implementación
  }

  /// Navega al listado una vez finalizada la sincronización.
  void finalizar() {
    Get.offAllNamed(AppRoutes.segmentos);
  }

  /// Vuelve a login si la sincronización no está activa.
  void volver() {
    if (isRunning.value) return;
    Get.offAllNamed(AppRoutes.login);
  }
}
