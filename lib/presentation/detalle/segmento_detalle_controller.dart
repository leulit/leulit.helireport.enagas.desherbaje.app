import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';

import '../../core/app_di.dart';
import '../../core/app_router.dart';
import '../../core/app_theme.dart';
import '../../core/app_typed_actions.dart';
import '../../core/gis/capture_meta.dart';
import '../../core/gis/media_gis_geojson.dart';
import '../../core/gis/media_gis_recorder.dart';
import '../../core/my_getx_controller.dart';
import '../../core/services/gasoductos_service.dart';
import '../../data/model/mensaje_entity.dart';
import '../../data/repository/auth_repository_impl.dart';
import '../../data/repository/imagen_repository_impl.dart';
import '../../data/repository/mensaje_segmento_repository.dart';
import '../../data/repository/segmento_repository_impl.dart';
import '../../data/repository/video_repository_impl.dart';
import '../../domain/entities/imagen_segmento_entity.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/entities/video_segmento_entity.dart';
import 'edit_extremos/edit_extremos_dialog.dart';
import 'segmento_media_item.dart';

class SegmentoDetalleController extends MyGetxController {
  static final Logger _log = Logger();

  SegmentoDetalleController({
    AuthRepositoryImpl? authRepo,
    SegmentoRepositoryImpl? segmentoRepo,
    ImagenRepositoryImpl? imagenRepo,
    VideoRepositoryImpl? videoRepo,
    MensajeSegmentoRepository? mensajeRepo,
    ImagePicker? picker,
  })  : _authRepo = authRepo ?? AuthRepositoryImpl(),
        _segmentoRepo = segmentoRepo ?? SegmentoRepositoryImpl(),
        _imagenRepo = imagenRepo ?? ImagenRepositoryImpl(),
        _videoRepo = videoRepo ?? VideoRepositoryImpl(),
        _mensajeRepo = mensajeRepo ?? MensajeSegmentoRepository(),
        _picker = picker ?? ImagePicker();

  final AuthRepositoryImpl _authRepo;
  final SegmentoRepositoryImpl _segmentoRepo;
  final ImagenRepositoryImpl _imagenRepo;
  final VideoRepositoryImpl _videoRepo;
  final MensajeSegmentoRepository _mensajeRepo;
  final ImagePicker _picker;

  late SegmentoEntity segmento;
  final user = Rx<UserModel?>(null);

  /// Controlador del mapa, expuesto para que los botones +/- de zoom puedan
  /// invocar `mapController.move`.
  final mapController = MapController();

  final _alignEnDispositivo = StreamController<double?>.broadcast();
  Stream<double?> get alignEnDispositivoStream => _alignEnDispositivo.stream;

  final estado = Rx<EstadoActividad>(EstadoActividad.propuesta);
  final tipoActividad = Rx<TipoActividad>(TipoActividad.desherbajeSelectivo);
  final descripcion = ''.obs;
  final isSaving = false.obs;

  /// Imágenes mostradas en los carruseles (remotas + capturadas localmente).
  final imagenes = <ImagenSegmentoEntity>[].obs;

  /// Vídeos locales pendientes + subidos para este segmento.
  final videos = <VideoSegmentoEntity>[].obs;

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

  GasoductosService get _gasoductosService => AppDI.gasoductosService;

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
    _loadVideos();
    _loadMensajes();
    _ensureGasoductos();

    onTypedAction<void>(AppTypedActions.guardarRequested, (_) => guardar());
    onTypedAction<void>(
        AppTypedActions.editarExtremosRequested, (_) => abrirEdicionExtremos());
    onTypedAction<TipoFoto>(AppTypedActions.capturaRequested, (event) {
      final tipo = event.data;
      if (tipo != null) capturarMedia(tipo);
    });
    onTypedAction<void>(AppTypedActions.centrarEnDispositivoRequested,
        (_) => _centrarEnDispositivo());
    onTypedAction<LatLngBounds>(AppTypedActions.mediaGisBoundsRequested,
        (event) => _fitMediaBounds(event.data));
    addWorker(ever<bool>(
        isSaving, (v) => AppTypedActions.savingChanged.dispatch(data: v)));
  }

  @override
  void onClose() {
    textMensajeController.dispose();
    mensajesScrollController.dispose();
    _alignEnDispositivo.close();
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

  /// A cloud media row (all media lives in the imagenes list on the backend) is a
  /// video when its mime type is video/* — with a filename/url extension fallback
  /// for legacy rows that lack a reliable mime type.
  static const Set<String> _videoExts = {
    'mp4',
    'mov',
    'm4v',
    'avi',
    'mkv',
    'webm',
    '3gp',
  };

  bool _esVideo(ImagenSegmentoEntity i) {
    if (i.mimeType.toLowerCase().startsWith('video/')) return true;
    // Fallback por extensión para filas legacy sin mime fiable. Se prueban
    // AMBAS fuentes (filename y url): un endpoint de descarga sin extensión
    // limpia (p.ej. `/videos/download/42`) no debe descartar un filename
    // `.mp4` válido. Se recorta el querystring antes de tomar la extensión.
    bool hasVideoExt(String? s) {
      if (s == null || s.isEmpty) return false;
      final ext = s.split('?').first.split('.').last.toLowerCase();
      return _videoExts.contains(ext);
    }

    return hasVideoExt(i.filename) || hasVideoExt(i.url);
  }

  /// Media combinada (fotos + videos, nube + local) de un [tipo], ordenada por
  /// fecha de captura ascendente. Lee ambas RxList para que el Obx reaccione a
  /// cualquiera. Un video de nube que ya existe como captura local (mismo
  /// clientId) se omite: gana la copia local (reproduce offline).
  List<SegmentoMediaItem> mediaPorTipo(TipoFoto tipo) {
    final tv = _tipoVideoDesde(tipo);
    final localVideoIds = <String>{
      for (final v in videos)
        if (v.tipoVideo == tv) v.clientId,
    };
    final items = <SegmentoMediaItem>[];
    for (final i in imagenes) {
      if (i.tipoFoto != tipo) continue;
      if (_esVideo(i)) {
        if (localVideoIds.contains(i.clientId)) continue; // dedup: local wins
        items.add(SegmentoMediaItem.remoteVideo(i));
      } else {
        items.add(SegmentoMediaItem.imagen(
          i,
          onDelete: i.isSubida ? null : () => confirmDeleteImagen(i),
        ));
      }
    }
    for (final v in videos) {
      if (v.tipoVideo != tv) continue;
      items.add(SegmentoMediaItem.localVideo(
        v,
        onDelete: v.isSubida ? null : () => confirmDeleteVideo(v),
      ));
    }
    items.sort((a, b) => a.capturadaAt.compareTo(b.capturadaAt));
    return items;
  }

  Future<void> _loadImagenes() async {
    final remote = segmento.imagenes;
    final local = await _imagenRepo.getAllByClientId(segmento.clientId);
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

  /// Recentra el mapa en la posición actual del dispositivo empujando el zoom
  /// actual al [alignEnDispositivoStream] que consume la capa de ubicación.
  void _centrarEnDispositivo() {
    _alignEnDispositivo.add(mapController.camera.zoom);
  }

  /// Ajusta la cámara del mapa embebido para encuadrar los bounds de la
  /// georreferencia de la media activa (emitidos por `MediaGisLayer`) con
  /// margen amplio. `maxZoom` acota el acercamiento cuando el bounds es un
  /// único punto (foto sin traza).
  void _fitMediaBounds(LatLngBounds? bounds) {
    if (bounds == null) return;
    mapController.fitCamera(CameraFit.bounds(
      bounds: bounds,
      padding: const EdgeInsets.all(80),
      maxZoom: 17,
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

  Future<void> _loadVideos() async {
    final local = await _videoRepo.getAllByClientId(segmento.clientId);
    videos.assignAll(local);
  }

  // ──────────────────────────── Captura de vídeo ───────────────────────────

  /// Construye la entidad de vídeo desde un path local y la persiste en el
  /// outbox. Reusada por la grabadora nativa (tab Vídeos) y por la pantalla
  /// de cámara con toggle foto/vídeo (tab Fotos).
  Future<void> _saveVideoFromPath(String path, TipoVideo tipo,
      {required bool saveToGallery,
      List<MediaGisSample> gis = const [],
      required MediaSource source}) async {
    try {
      final file = File(path);
      final tamanyoBytes = await file.length();
      final filename = path.split('/').last;
      final ext = filename.split('.').last.toLowerCase();
      final mimeType = switch (ext) {
        'mp4' => 'video/mp4',
        'mov' => 'video/quicktime',
        'm4v' => 'video/x-m4v',
        _ => 'video/mp4',
      };

      final meta = await captureMeta();
      final gisJson = buildVideoGeoJson(gis,
          userId: user.value?.id, meta: meta, source: source);

      final video = VideoSegmentoEntity(
        actividadId: 0,
        segmentoId: segmento.id ?? 0,
        segmentoClientId: segmento.clientId,
        tipoVideo: tipo,
        filename: filename,
        ruta: path,
        capturadaAt: DateTime.now(),
      )
        ..mimeType = mimeType
        ..tamanyoBytes = tamanyoBytes
        ..gisJson = gisJson;

      await _videoRepo.saveLocal(video);
      await _loadVideos();
      if (saveToGallery) await _saveToGallery(path, isVideo: true);
    } catch (e, st) {
      _log.e('SegmentoDetalleController: error al guardar vídeo',
          error: e, stackTrace: st);
      _showSnack(
        title: 'Error',
        message: 'No se ha podido guardar el vídeo: $e',
        isError: true,
      );
    }
  }

  // ──────────────────────────── Captura de foto ────────────────────────────

  /// Pide el origen (galería / cámara) y persiste la captura como foto o vídeo
  /// del [tipo] indicado. La cámara propia ofrece toggle foto/vídeo (vídeo sin
  /// audio). Las capturas de cámara se copian además a la galería del
  /// dispositivo; las elegidas de galería no (ya están allí).
  Future<void> capturarMedia(TipoFoto tipo) async {
    final source = await _showSourceDialog(tipo);
    if (source == null) return;

    if (source == _PickSource.gallery) {
      // Media elegida de galería: sin GIS (no hay fix de captura en tiempo real).
      final xFile = await _picker.pickMedia(imageQuality: 85);
      final path = xFile?.path;
      if (path == null || path.isEmpty) return;
      if (_isVideoPath(path)) {
        await _saveVideoFromPath(path, _tipoVideoDesde(tipo),
            saveToGallery: false, source: MediaSource.gallery);
      } else {
        await _addImagen(path, tipo,
            saveToGallery: false, gis: null, source: MediaSource.gallery);
      }
      return;
    }

    // Cámara: pantalla propia con toggle foto/vídeo. Devuelve
    // `({String path, bool isVideo, Object? gis})` o null si el usuario cancela.
    // `gis` es MediaGisSample? para foto y List<MediaGisSample> para vídeo.
    // GetX construye GetPageRoute<dynamic>; navegar dynamic y castear el result.
    final result = await Get.toNamed<dynamic>(AppRoutes.camera);
    if (result == null) return;
    final capture = result as ({String path, bool isVideo, Object? gis});
    if (capture.path.isEmpty) return;
    if (capture.isVideo) {
      final gis =
          (capture.gis as List<MediaGisSample>?) ?? const <MediaGisSample>[];
      await _saveVideoFromPath(capture.path, _tipoVideoDesde(tipo),
          saveToGallery: true, gis: gis, source: MediaSource.camera);
    } else {
      await _addImagen(capture.path, tipo,
          saveToGallery: true,
          gis: capture.gis as MediaGisSample?,
          source: MediaSource.camera);
    }
  }

  /// Mapea el tipo de foto (antes/después) al tipo de vídeo equivalente para
  /// los vídeos grabados desde la pantalla de cámara del tab Fotos.
  TipoVideo _tipoVideoDesde(TipoFoto tipo) =>
      tipo == TipoFoto.antes ? TipoVideo.antes : TipoVideo.despues;

  /// Heurística por extensión para distinguir vídeos elegidos de la galería
  /// (image_picker `pickMedia` devuelve foto o vídeo sin discriminar el tipo).
  bool _isVideoPath(String path) {
    const exts = {'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm', '3gp'};
    return exts.contains(path.split('.').last.toLowerCase());
  }

  Future<_PickSource?> _showSourceDialog(TipoFoto tipo) async {
    return Get.dialog<_PickSource>(
      AlertDialog(
        title: Text(
          tipo == TipoFoto.antes
              ? 'Capturar foto/vídeo antes'
              : 'Capturar foto/vídeo después',
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

  Future<void> _addImagen(
    String localPath,
    TipoFoto tipo, {
    required bool saveToGallery,
    required MediaGisSample? gis,
    required MediaSource source,
  }) async {
    final filename = localPath.split('/').last;
    final meta = await captureMeta();
    final gisJson = buildPhotoGeoJson(gis,
        userId: user.value?.id, meta: meta, source: source);
    final imagen = ImagenSegmentoEntity(
      actividadId: 0,
      segmentoId: segmento.id ?? 0,
      segmentoClientId: segmento.clientId,
      tipoFoto: tipo,
      filename: filename,
      ruta: localPath,
      capturadaAt: DateTime.now(),
    )..gisJson = gisJson;
    try {
      await _imagenRepo.saveLocal(imagen);
      await _loadImagenes();
      if (saveToGallery) await _saveToGallery(localPath, isVideo: false);
    } catch (e) {
      _showSnack(
        title: 'Error',
        message: 'No se ha podido guardar la foto: $e',
        isError: true,
      );
    }
  }

  /// Copia la captura a la galería del dispositivo (best-effort). Un fallo de
  /// galería no debe abortar el guardado local: se registra y se continúa.
  Future<void> _saveToGallery(String path, {required bool isVideo}) async {
    try {
      if (isVideo) {
        await Gal.putVideo(path);
      } else {
        await Gal.putImage(path);
      }
    } on GalException catch (e, st) {
      _log.w('No se pudo guardar en galería (${e.type})',
          error: e, stackTrace: st);
    }
  }

  /// Confirma y elimina una foto (solo capturas locales no subidas).
  Future<void> confirmDeleteImagen(ImagenSegmentoEntity imagen) async {
    if (await _confirmDelete(isVideo: false)) await _deleteImagen(imagen);
  }

  /// Confirma y elimina un vídeo (solo capturas locales no subidas).
  Future<void> confirmDeleteVideo(VideoSegmentoEntity video) async {
    if (await _confirmDelete(isVideo: true)) await _deleteVideo(video);
  }

  Future<bool> _confirmDelete({required bool isVideo}) async {
    final res = await Get.dialog<bool>(
      AlertDialog(
        title: Text(isVideo ? 'Eliminar vídeo' : 'Eliminar foto'),
        content: Text(
          '¿Seguro que quieres eliminar ${isVideo ? 'el vídeo' : 'la foto'}? '
          'Se borrará de la app y de la base de datos local.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back<bool>(result: false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Get.back<bool>(result: true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      barrierDismissible: false,
    );
    return res ?? false;
  }

  Future<void> _deleteImagen(ImagenSegmentoEntity imagen) async {
    try {
      await _imagenRepo.purgeLocal(imagen);
      imagenes.removeWhere((i) => i.clientId == imagen.clientId);
      await _deleteLocalFile(imagen.ruta);
    } catch (e) {
      _showSnack(
        title: 'Error',
        message: 'No se pudo eliminar la foto: $e',
        isError: true,
      );
    }
  }

  Future<void> _deleteVideo(VideoSegmentoEntity video) async {
    try {
      await _videoRepo.purgeLocal(video);
      videos.removeWhere((v) => v.clientId == video.clientId);
      await _deleteLocalFile(video.ruta);
    } catch (e) {
      _showSnack(
        title: 'Error',
        message: 'No se pudo eliminar el vídeo: $e',
        isError: true,
      );
    }
  }

  /// Borra el fichero de captura del almacenamiento de la app (best-effort).
  Future<void> _deleteLocalFile(String path) async {
    if (path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e, st) {
      _log.w('No se pudo borrar fichero local: $path',
          error: e, stackTrace: st);
    }
  }

  // ──────────────────────────── Mensajes — fetch / send ────────────────────

  /// Offline-first, idéntico a [_loadImagenes]: los mensajes de nube viajan
  /// embebidos en `segmento.mensajes[]` (pull); los nuevos viven en el store
  /// local. Merge por `clientId`, ordenado cronológicamente ascendente.
  Future<void> _loadMensajes() async {
    final remote = segmento.mensajes;
    final local =
        await _mensajeRepo.getAllBySegmentoClientId(segmento.clientId);
    final extras =
        local.where((l) => !remote.any((r) => r.clientId == l.clientId));
    final all = [...remote, ...extras]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    mensajes.assignAll(all);
  }

  Future<void> sendMensaje() async {
    final text = textMensajeController.text.trim();
    if (text.isEmpty || isSendingMensaje.value) return;

    final me = user.value;
    final myId = me?.id ?? 0;

    // Insert optimista al principio (la lista se pinta con `reverse: true` →
    // index 0 == último cronológico). Limpiamos el input antes de persistir.
    final optimistic = MensajeSegmentoEntity(
      segmentoId: segmento.id ?? 0,
      segmentoClientId: segmento.clientId,
      mensaje: text,
      enviadoPor: myId,
    );
    mensajes.insert(0, optimistic);
    textMensajeController.clear();
    _scrollToBottom();

    isSendingMensaje.value = true;
    final result = await _mensajeRepo.add(
      segmentoId: segmento.id ?? 0,
      segmentoClientId: segmento.clientId,
      mensaje: text,
      enviadoPor: myId,
    );
    if (result.isSuccess) {
      // Reemplaza el placeholder por la entidad realmente persistida (mismo
      // clientId que en el store) para que un reload posterior deduplique bien.
      final saved = result.dataOrNull;
      if (saved != null) {
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
