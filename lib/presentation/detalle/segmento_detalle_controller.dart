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
  SegmentoDetalleController({
    AuthRepositoryImpl? authRepo,
    SegmentoRepositoryImpl? segmentoRepo,
    ImagenRepositoryImpl? imagenRepo,
    MensajeSegmentoRepository? mensajeRepo,
    ImagePicker? picker,
  })  : _authRepo = authRepo ?? AuthRepositoryImpl(),
        _segmentoRepo = segmentoRepo ?? SegmentoRepositoryImpl(),
        _imagenRepo = imagenRepo ?? ImagenRepositoryImpl(),
        _mensajeRepo = mensajeRepo ?? MensajeSegmentoRepository(),
        _picker = picker ?? ImagePicker();

  final AuthRepositoryImpl _authRepo;
  final SegmentoRepositoryImpl _segmentoRepo;
  final ImagenRepositoryImpl _imagenRepo;
  final MensajeSegmentoRepository _mensajeRepo;
  final ImagePicker _picker;

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
          tipo == TipoFoto.antes
              ? 'Capturar foto antes'
              : 'Capturar foto después',
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
    final filename = localPath.split('/').last;
    final imagen = ImagenSegmentoEntity(
      actividadId: 0,
      // FK por id remoto; A4 migrará a clientId de segmento (fuera de alcance).
      // local-only: 0 hasta que el segmento sincronice y obtenga id remoto.
      segmentoId: segmento.id ?? 0,
      tipoFoto: tipo,
      filename: filename,
      ruta: localPath,
      capturadaAt: DateTime.now(),
    );
    try {
      await _imagenRepo.saveLocal(imagen);
      await _loadImagenes();
    } catch (e) {
      _showSnack(
        title: 'Error',
        message: 'No se ha podido guardar la foto: $e',
        isError: true,
      );
    }
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
  ///
  /// Valida la transición de estado contra la matriz SSOT
  /// (`EstadoActividad.puedeIrA`) antes de persistir. Los estados sin
  /// transición de salida (`propuesta`, `validada`, `cerrada`) son de solo
  /// lectura desde la app de campo. Si la transición no procede, muestra un
  /// diálogo informativo y aborta el guardado.
  Future<void> guardar() async {
    if (!_validateEstado()) return;

    isSaving.value = true;
    try {
      segmento.estado = estado.value;
      segmento.tipoActividad = tipoActividad.value;
      segmento.descripcion = descripcion.value;
      await _segmentoRepo.saveLocal(segmento);
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

  /// Valida la transición de estado contra la matriz SSOT
  /// (`EstadoActividad.transicionesPermitidas`). Defensa en profundidad: el
  /// dropdown ya oculta destinos inválidos; esto es la red de seguridad antes
  /// de persistir. Devuelve `false` y muestra un diálogo si no procede.
  bool _validateEstado() {
    final origen = segmento.estado; // estado original cargado del backend
    final destino = estado.value;

    if (!origen.esEditableDesdeApp) {
      _dialogEstadoBloqueado(origen);
      return false;
    }
    if (!origen.puedeIrA(destino)) {
      _dialogTransicionInvalida(origen, destino);
      return false;
    }
    return true;
  }

  void _dialogEstadoBloqueado(EstadoActividad origen) {
    final extra = origen == EstadoActividad.cerrada
        ? 'La tarea está cerrada y no admite más cambios.'
        : 'Podrás trabajar sobre la tarea cuando el gestor la pase a "Contratista".';
    Get.dialog<void>(
      AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.lock_outline, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Expanded(child: Text('Estado no editable')),
          ],
        ),
        content: Text(
          'El estado "${origen.etiqueta}" no se puede modificar desde la app '
          'de campo.\n\n$extra',
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Entendido')),
        ],
      ),
      barrierDismissible: false,
    );
  }

  void _dialogTransicionInvalida(
      EstadoActividad origen, EstadoActividad destino) {
    final permitidos =
        origen.transicionesPermitidas.map((e) => e.etiqueta).join(', ');
    Get.dialog<void>(
      AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Expanded(child: Text('Cambio de estado no permitido')),
          ],
        ),
        content: Text(
          'No se puede pasar de "${origen.etiqueta}" a "${destino.etiqueta}".'
          '\n\nDesde "${origen.etiqueta}" solo se permite: $permitidos.',
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Entendido')),
        ],
      ),
      barrierDismissible: false,
    );
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
