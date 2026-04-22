import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../core/my_getx_controller.dart';
import '../../core/services/gasoductos_service.dart';
import '../../data/model/mensaje_entity.dart';
import '../../data/repository/auth_repository_impl.dart';
import '../../data/repository/imagen_repository_impl.dart';
import '../../data/repository/mensaje_segmento_repository.dart';
import '../../data/repository/segmento_repository_impl.dart';
import '../../domain/entities/imagen_segmento_entity.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/entities/user_entity.dart';
import 'edit_extremos/edit_extremos_dialog.dart';

class SegmentoDetalleController extends MyGetxController {
  final _authRepo = AuthRepositoryImpl();
  final _segmentoRepo = SegmentoRepositoryImpl();
  final _imagenRepo = ImagenRepositoryImpl();
  final _mensajeRepo = MensajeSegmentoRepository();
  final _picker = ImagePicker();

  late SegmentoEntity segmento;
  final user = Rx<UserModel?>(null);

  /// Controlador del mapa, expuesto para que los botones +/- de zoom puedan
  /// invocar `mapController.move`.
  final mapController = MapController();

  final estado = Rx<EstadoActividad>(EstadoActividad.propuesta);
  final tipoActividad = Rx<TipoActividad>(TipoActividad.desherbajeSelectivo);
  final descripcion = ''.obs;
  final isSaving = false.obs;

  /// Imágenes mostradas en los carruseles (remotas + capturadas localmente).
  final imagenes = <ImagenSegmentoEntity>[].obs;

  // ──────────────────────────── Mensajes ────────────────────────────
  final mensajes = <MensajeSegmentoEntity>[].obs;
  final isLoadingMensajes = false.obs;
  final isSendingMensaje = false.obs;
  final textMensajeController = TextEditingController();
  final mensajesScrollController = ScrollController();

  late final LatLng initialCenter;
  late final double initialZoom;
  final highlightedSegment = Rx<Polyline>(Polyline(points: const []));

  /// Encuadre inicial del mapa embebido. Si la traza tiene ≥2 puntos usa
  /// `CameraFit.bounds` para garantizar que todo el segmento quepa con
  /// padding; si no, se cae a `initialCenter`/`initialZoom`.
  CameraFit? get initialCameraFit {
    final pts = segmento.ubicacionGis;
    if (pts.length < 2) return null;
    return CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(pts),
      padding: const EdgeInsets.all(40),
      maxZoom: 19,
    );
  }

  final gasoductosPolylines = <Polyline>[].obs;

  GasoductosService get _gasoductosService => Get.find<GasoductosService>();

  @override
  void myOnInit() {
    final args = Get.arguments;
    segmento = args is SegmentoEntity ? args : SegmentoEntity.empty();
    estado.value = segmento.estado;
    tipoActividad.value = segmento.tipoActividad;
    descripcion.value = segmento.descripcion;

    _initMap();
    _loadUser();
    _loadImagenes();
    _loadMensajes();
    _ensureGasoductos();
  }

  @override
  void onClose() {
    textMensajeController.dispose();
    mensajesScrollController.dispose();
    super.onClose();
  }

  Future<void> _loadUser() async {
    user.value = await _authRepo.getCurrentUser();
  }

  String get ctName {
    final name = user.value?.ctNameById(segmento.ctId);
    if (name != null && name.isNotEmpty) return name;
    return 'CT ${segmento.ctId}';
  }

  /// Imágenes filtradas por tipo (antes / después) para los carruseles.
  List<ImagenSegmentoEntity> imagenesPorTipo(TipoFoto tipo) =>
      imagenes.where((i) => i.tipoFoto == tipo).toList();

  Future<void> _loadImagenes() async {
    final remote = segmento.imagenes;
    final segId = segmento.id;
    if (segId == null) {
      imagenes.assignAll(remote);
      return;
    }
    final local = await _imagenRepo.getAllBySegmento(segId);
    final extras =
        local.where((l) => !remote.any((r) => r.clientId == l.clientId));
    imagenes.assignAll([...remote, ...extras]);
  }

  void _initMap() {
    final pts = segmento.ubicacionGis;
    if (pts.isNotEmpty) {
      initialCenter = pts[pts.length ~/ 2];
      initialZoom = 16;
    } else if (segmento.latInicio != null && segmento.lngInicio != null) {
      initialCenter = LatLng(segmento.latInicio!, segmento.lngInicio!);
      initialZoom = 15;
    } else {
      initialCenter = const LatLng(40.4168, -3.7038);
      initialZoom = 7;
    }

    highlightedSegment.value = Polyline(
      points: pts.isEmpty ? const [] : pts,
      color: const Color(0xFFFFC107),
      strokeWidth: 6,
      borderColor: Colors.white,
      borderStrokeWidth: 2,
    );
  }

  /// Abre el diálogo de edición de extremos. Al volver con una entidad
  /// actualizada, refresca la polilínea destacada en el mapa embebido y
  /// mueve la cámara al nuevo centro.
  Future<void> abrirEdicionExtremos() async {
    final updated = await Get.dialog<SegmentoEntity?>(
      EditExtremosDialog(segmento: segmento),
      barrierDismissible: false,
    );
    if (updated == null) return;
    segmento = updated;

    final pts = updated.ubicacionGis;
    highlightedSegment.value = Polyline(
      points: pts.isEmpty ? const [] : pts,
      color: const Color(0xFFFFC107),
      strokeWidth: 6,
      borderColor: Colors.white,
      borderStrokeWidth: 2,
    );

    if (pts.length >= 2) {
      mapController.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(40),
        maxZoom: 19,
      ));
    } else if (updated.latInicio != null && updated.lngInicio != null) {
      mapController.move(
        LatLng(updated.latInicio!, updated.lngInicio!),
        mapController.camera.zoom,
      );
    }

    _showSnack(
      title: 'Extremos actualizados',
      message: 'Los extremos del segmento se han guardado localmente',
      isError: false,
    );
  }

  Future<void> _ensureGasoductos() async {
    await _gasoductosService.ensureLoaded();
    gasoductosPolylines.assignAll(_gasoductosService.polylines);
    addWorker(ever<List<Polyline>>(
      _gasoductosService.polylines,
      gasoductosPolylines.assignAll,
    ));
  }

  void zoomIn() {
    final cam = mapController.camera;
    mapController.move(cam.center, (cam.zoom + 1).clamp(5, 20));
  }

  void zoomOut() {
    final cam = mapController.camera;
    mapController.move(cam.center, (cam.zoom - 1).clamp(5, 20));
  }

  // ──────────────────────────── Captura de foto ────────────────────────────

  /// Pide al usuario el origen (galería / cámara), obtiene el path y lo
  /// persiste como `ImagenSegmentoEntity` del [tipo] indicado.
  Future<void> capturarFoto(TipoFoto tipo) async {
    final source = await _showSourceDialog(tipo);
    if (source == null) return;

    String? path;
    if (source == _PickSource.gallery) {
      final xFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      path = xFile?.path;
    } else {
      path = await Get.toNamed<String?>(AppRoutes.camera);
    }

    if (path == null || path.isEmpty) return;
    await _addImagen(path, tipo);
  }

  Future<_PickSource?> _showSourceDialog(TipoFoto tipo) async {
    return Get.dialog<_PickSource>(
      AlertDialog(
        title: Text(
          tipo == TipoFoto.antes ? 'Capturar foto antes' : 'Capturar foto después',
          style: const TextStyle(fontSize: 16),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.moduleGreen),
              title: const Text('Galería'),
              onTap: () => Get.back<_PickSource>(result: _PickSource.gallery),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_camera, color: AppColors.moduleGreen),
              title: const Text('Cámara'),
              onTap: () => Get.back<_PickSource>(result: _PickSource.camera),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back<_PickSource>(result: null),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _addImagen(String localPath, TipoFoto tipo) async {
    final segId = segmento.id;
    if (segId == null) return;
    final filename = localPath.split('/').last;
    final imagen = ImagenSegmentoEntity(
      actividadId: 0,
      segmentoId: segId,
      tipoFoto: tipo,
      filename: filename,
      ruta: localPath,
      capturadaAt: DateTime.now(),
    );
    await _imagenRepo.saveLocal(imagen);
    await _loadImagenes();
  }

  // ──────────────────────────── Mensajes — fetch / send ────────────────────

  Future<void> _loadMensajes() async {
    final segId = segmento.id;
    if (segId == null) return;
    isLoadingMensajes.value = true;
    final result = await _mensajeRepo.mensajesBySegmento(id: segId);
    if (result.isSuccess) {
      mensajes.assignAll(result.dataOrNull ?? const <MensajeSegmentoEntity>[]);
    }
    isLoadingMensajes.value = false;
  }

  Future<void> sendMensaje() async {
    final text = textMensajeController.text.trim();
    if (text.isEmpty || isSendingMensaje.value) return;

    final segId = segmento.id;
    if (segId == null) return;

    final me = user.value;
    final myId = me?.id ?? 0;

    // Insert optimista al principio (la lista se pinta con `reverse: true` →
    // index 0 == último cronológico). Limpiamos el input antes de la red.
    final optimistic = MensajeSegmentoEntity(
      segmentoId: segId,
      mensaje: text,
      enviadoPor: myId,
    );
    mensajes.insert(0, optimistic);
    textMensajeController.clear();
    _scrollToBottom();

    isSendingMensaje.value = true;
    final result = await _mensajeRepo.add(
      segmentoId: segId,
      mensaje: text,
      enviadoPor: myId,
    );
    if (result.isSuccess) {
      final saved = result.dataOrNull;
      if (saved != null && saved.id != null) {
        mensajes[0] = saved;
      }
    }
    isSendingMensaje.value = false;
  }

  void _scrollToBottom() {
    if (!mensajesScrollController.hasClients) return;
    mensajesScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Offline-first: persiste en SQLite todas las ediciones (estado / tipo /
  /// descripción) marcándolas como pendientes de sync, y como best-effort
  /// intenta propagar al backend el cambio de estado. Muestra feedback al
  /// usuario y se queda en la misma página.
  Future<void> guardar() async {
    isSaving.value = true;
    try {
      segmento.estado = estado.value;
      segmento.tipoActividad = tipoActividad.value;
      segmento.descripcion = descripcion.value;
      if (segmento.id != null) {
        await _segmentoRepo.saveLocal(segmento);
        await _segmentoRepo.updateEstado(segmento.id!, estado.value);
      }
      _showSnack(
        title: 'Guardado',
        message: 'Cambios guardados correctamente',
        isError: false,
      );
    } catch (e) {
      _showSnack(
        title: 'Error',
        message: 'No se han podido guardar los cambios: $e',
        isError: true,
      );
    } finally {
      isSaving.value = false;
    }
  }

  void _showSnack({
    required String title,
    required String message,
    required bool isError,
  }) {
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: isError ? Colors.red.shade700 : AppColors.moduleGreen,
      colorText: Colors.white,
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 2),
    );
  }
}

enum _PickSource { gallery, camera }
