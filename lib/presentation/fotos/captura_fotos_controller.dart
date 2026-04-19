import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/services/connectivity_service.dart';
import '../../data/model/mensaje_entity.dart';
import '../../data/network/network_service.dart';
import '../../data/repository/imagen_repository_impl.dart';
import '../../domain/entities/imagen_segmento_entity.dart';
import '../../domain/entities/actividad_entity.dart';
import '../../domain/entities/segmento_entity.dart';

class CapturaFotosController extends GetxController {

  List<String> mockFotosAntes = [
    'https://enagastool.helireport.com/incidencias/thumbdb/329276/310/170?t=1774942853274',
    'https://enagastool.helireport.com/incidencias/thumbdb/329274/310/170?t=1774942886813'
  ];
  List<String> mockFotosDespues = [
    'https://enagastool.helireport.com/incidencias/thumbdb/329277/310/170?t=1774942794953',
    'https://enagastool.helireport.com/incidencias/thumbdb/329272/310/170?t=1774942908297'
  ];

  final mensajesScrollController = ScrollController();  
  final textMensajeController = TextEditingController();
  List<MensajeEntity> mensajes = <MensajeEntity>[].obs;

  final _repo = ImagenRepositoryImpl();
  final _picker = ImagePicker();

  Rx<int> updUI = 0.obs;

  late final SegmentoEntity segmento;
  late final Rx<EstadoActividad> estadoSegmento;

  final imagenes = <ImagenSegmentoEntity>[].obs;
  final isUploading = false.obs;
  final uploadCurrent = 0.obs;
  final uploadTotal = 0.obs;

  List<ImagenSegmentoEntity> get imagenesAntes => imagenes.where((i) => i.tipoFoto == TipoFoto.antes).toList();

  List<ImagenSegmentoEntity> get imagenesDespues => imagenes.where((i) => i.tipoFoto == TipoFoto.despues).toList();

  int get pendientes => imagenes.where((i) => i.syncStatus == SyncStatus.pending).length;

  int get subidas => imagenes.where((i) => i.syncStatus == SyncStatus.uploaded).length;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    segmento = args['segmento'] as SegmentoEntity;
    estadoSegmento = segmento.estado.obs;
    _loadImagenes();
    _loadMensajes();
    Get.find<ConnectivityService>().addSyncListener(_onConnectivityRestored);
  }

  Future<void> _loadMensajes() async {
    try {
      final url = "http://enagastool.helireport.com/actividades/mensajesbyidsedmento/${segmento.id}";
      final response = await Get.find<NetworkService>().dio.get(url);
      
      if (response.data is List) {
        mensajes = (response.data as List)
            .map((item) => MensajeEntity.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      updUI.value++;
    } finally {
    }
  }  

  void sendMensaje() {
    final text = textMensajeController.text.trim();
    if (text.isEmpty) return;

    textMensajeController.clear();
    mensajes.insert(
      0,
      MensajeEntity(
        senderUserId: 0,
        mensaje: text,
        sentAt: DateTime.now(),
      ),
    );

    if (mensajesScrollController.hasClients) {
      mensajesScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> cambiarEstadoSegmento(EstadoActividad nuevoEstado) async {
    segmento.estado = nuevoEstado;
    estadoSegmento.value = nuevoEstado;
    try {
      await Get.find<NetworkService>().dio.post(
        'http://enagastool.helireport.com/actividades/update_estado_segmento',
        data: {'segmento_id': segmento.id, 'estado': nuevoEstado.descripcion},
      );
    } catch (_) {
      // Se reintentará cuando vuelva conectividad
    }
  }

  void _onConnectivityRestored() {
    if (pendientes > 0) uploadPending();
  }

  @override
  void onClose() {
    Get.find<ConnectivityService>().removeSyncListener(_onConnectivityRestored);
    super.onClose();
  }

  Future<void> _loadImagenes() async {
    //final imgs = await _repo.getAllByActividad(actividad.id);
    // Mostrar solo las fotos del segmento actual
    /*
    final segId = segmento.id ?? segmento.ctId;
    imagenes.assignAll(
      imgs.where((i) => i.segmentoId == segId).toList(),
    );
    */
  }

  Future<void> capturePhoto(TipoFoto tipo) async {
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (xFile == null) return;
    await _addImagen(xFile.path, tipo);
  }

  Future<void> _addImagen(String localPath, TipoFoto tipo) async {
    final imagen = ImagenSegmentoEntity(
      localId: const Uuid().v4(),
      actividadId: segmento.actividadId,
      segmentoId: segmento.id,
      localPath: localPath,
      tipoFoto: tipo,
      capturedAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
    );
    await _repo.saveLocal(imagen);
    imagenes.add(imagen);
  }

  Future<void> uploadPending() async {
    final pending =
        imagenes.where((i) => i.syncStatus == SyncStatus.pending).toList();
    if (pending.isEmpty) return;

    isUploading.value = true;
    uploadTotal.value = pending.length;
    uploadCurrent.value = 0;

    for (final img in pending) {
      uploadCurrent.value++;
      img.syncStatus = SyncStatus.uploading;
      imagenes.refresh();
      try {
        await _repo.uploadPending(segmento.id!);
      } catch (_) {}
    }

    await _loadImagenes();
    isUploading.value = false;
  }

  Future<void> deleteImagen(ImagenSegmentoEntity imagen) async {
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Eliminar foto'),
        content: const Text('¿Seguro que quieres eliminar esta foto?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Eliminar',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _repo.delete(imagen.localId);
      imagenes.remove(imagen);
    }
  }

  Future<void> guardar() async {
    await Future.wait([
      _syncSegmento(),
      if (pendientes > 0) uploadPending(),
    ]);
    Get.back();
  }

  Future<void> _syncSegmento() async {
    try {
      await Get.find<NetworkService>().dio.post(
        'http://enagastool.helireport.com/actividades/update_segmento',
        data: segmento.toJson(),
      );
    } catch (_) {
      // Fallo silencioso — el estado local ya está actualizado
    }
  }
}
