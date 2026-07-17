import 'package:get/get.dart';
import 'package:helireport_desherbaje/core/my_getx_controller.dart';
import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';

import '../../core/app_log.dart';
import '../../core/result/data_result.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/sync/engine/sync_engine.dart';
import '../../data/repository/auth_repository_impl.dart';
import '../../data/sync/imagen_local_store.dart';
import '../../data/sync/mensaje_local_store.dart';
import '../../data/sync/propagate_segmento_remote_id_usecase.dart';
import '../../data/sync/purge_synced_segmento_usecase.dart';
import '../../data/sync/segmento_local_store.dart';
import '../../data/sync/video_local_store.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repository/auth_repository.dart';
import '../../domain/usecases/get_segmentos_usecase.dart';

/// Controller de la página "Forzar envío a nube".
///
/// Expone el mismo modelo de filtros que [SegmentosListController] —texto,
/// estado y tipo— pero lista los segmentos en plano (sin agrupar por CT).
class ForzarEnvioController extends MyGetxController {
  ForzarEnvioController(
    this._useCase,
    this._engine,
    this._connectivity, {
    AuthRepository? authRepository,
    PurgeSyncedSegmentoUseCase? purgeUseCase,
    ImagenLocalStore? imagenStore,
    VideoLocalStore? videoStore,
    MensajeLocalStore? mensajeStore,
    PropagateSegmentoRemoteIdUseCase? propagate,
    SegmentoLocalStore? segmentoStore,
  })  : _authRepo = authRepository ?? AuthRepositoryImpl(),
        _purge = purgeUseCase ?? PurgeSyncedSegmentoUseCase(),
        _imagenStore = imagenStore ?? DI.get<ImagenLocalStore>(),
        _videoStore = videoStore ?? DI.get<VideoLocalStore>(),
        _mensajeStore = mensajeStore ?? DI.get<MensajeLocalStore>(),
        _propagate = propagate ?? PropagateSegmentoRemoteIdUseCase(),
        _segmentoStore = segmentoStore ?? DI.get<SegmentoLocalStore>();

  final GetSegmentosUseCase _useCase;
  final SyncEngine _engine;
  final ConnectivityService _connectivity;
  final AuthRepository _authRepo;
  final PurgeSyncedSegmentoUseCase _purge;
  final ImagenLocalStore _imagenStore;
  final VideoLocalStore _videoStore;
  final MensajeLocalStore _mensajeStore;
  final PropagateSegmentoRemoteIdUseCase _propagate;
  final SegmentoLocalStore _segmentoStore;

  final segmentos = <SegmentoEntity>[].obs;
  final filtradas = <SegmentoEntity>[].obs;
  final isLoading = false.obs;
  final error = Rx<String?>(null);

  final selectedEstado = Rx<EstadoActividad?>(null);
  final selectedTipo = Rx<TipoActividad?>(null);
  final selectedCt = Rx<int?>(null);
  final filterDescripcion = ''.obs;

  final enviandoIds = <int>{}.obs;
  final isEnviandoTodos = false.obs;

  /// Último resumen de envío (subidos / reintentables / rechazados / conflictos).
  final lastDrainSummary = Rx<DrainSummary?>(null);

  /// Mensaje de error del último envío (vacío si no hubo error).
  final lastError = ''.obs;

  UserModel? _user;

  @override
  void myOnInit() {
    debounce(
      filterDescripcion,
      (_) => _applyFilter(),
      time: const Duration(milliseconds: 300),
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _user = await _authRepo.getCurrentUser();
    await loadSegmentos();
  }

  String ctNameById(int ctId) {
    final name = _user?.ctNameById(ctId);
    if (name != null && name.isNotEmpty) return name;
    return 'CT $ctId';
  }

  Future<void> loadSegmentos() async {
    isLoading.value = true;
    error.value = null;
    final result = await _useCase.execute();
    switch (result) {
      case DataSuccess(:final data):
        segmentos.assignAll(
          data.where((s) => s.estado == EstadoActividad.finalizada),
        );
        _applyFilter();
      case DataFailure(:final message):
        error.value = message;
    }
    isLoading.value = false;
  }

  void filterByEstado(EstadoActividad? estado) {
    selectedEstado.value = estado;
    _applyFilter();
  }

  void filterByTipo(TipoActividad? tipo) {
    selectedTipo.value = tipo;
    _applyFilter();
  }

  void filterByCt(int? ctId) {
    selectedCt.value = ctId;
    _applyFilter();
  }

  /// Lista de CTs presentes en los segmentos cargados, ordenados por nombre.
  List<int> get ctsDisponibles {
    final ids = segmentos.map((s) => s.ctId).toSet().toList();
    ids.sort((a, b) => ctNameById(a).compareTo(ctNameById(b)));
    return ids;
  }

  void _applyFilter() {
    final query = filterDescripcion.value.trim().toLowerCase();
    final estado = selectedEstado.value;
    final tipo = selectedTipo.value;
    final ct = selectedCt.value;

    filtradas.assignAll(segmentos.where((s) {
      if (estado != null && s.estado != estado) return false;
      if (tipo != null && s.tipoActividad != tipo) return false;
      if (ct != null && s.ctId != ct) return false;
      if (query.isNotEmpty && !s.descripcion.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }));
  }

  /// Suma dos [DrainSummary].
  DrainSummary _accumulate(DrainSummary a, DrainSummary b) => DrainSummary(
        succeeded: a.succeeded + b.succeeded,
        retryable: a.retryable + b.retryable,
        rejected: a.rejected + b.rejected,
        conflicts: a.conflicts + b.conflicts,
        authExpired: a.authExpired || b.authExpired,
      );

  /// Envía a la nube todo el contenido de un segmento y, si todo queda
  /// sincronizado, dispara `sync-complete` + purga local (dentro de
  /// [PurgeSyncedSegmentoUseCase.purgeIfFullySynced]).
  ///
  /// Orden: PRIMERO el segmento (upsert), para obtener/confirmar su id de
  /// backend; ese id se propaga a las filas hijas locales (imagen/video/
  /// mensaje, vía [PropagateSegmentoRemoteIdUseCase]) ANTES de drenarlas —
  /// si el segmento es nuevo, sus hijos aún llevan `segmento_id` a 0/null y
  /// subirían sin vínculo si se enviaran antes. Después: vídeos → fotos →
  /// mensajes. Solo los jobs de ESE segmento. Un fallo del segmento aborta
  /// sin tocar los hijos; un fallo de un hijo deja el segmento pendiente sin
  /// tocar a los demás segmentos.
  Future<DrainSummary> _sendOne(SegmentoEntity s) async {
    AppLog.i('ForzarEnvioController._sendOne(${s.id}): drenando "segmento"...');
    final segSummary =
        await _engine.drain(entityType: 'segmento', onlyClientIds: {s.clientId});

    if (segSummary.authExpired ||
        segSummary.rejected > 0 ||
        segSummary.retryable > 0 ||
        segSummary.conflicts > 0) {
      return segSummary; // el segmento no sincronizó limpio: no tocar hijos
    }

    final fresh = await _segmentoStore.findByClientId(s.clientId);
    final backendId = fresh?.id;
    if (backendId == null) {
      // Defensivo: el upsert no devolvió id pese a no reportar fallo.
      return segSummary;
    }

    await _propagate.propagate(s.clientId, backendId);

    final videoIds = (await _videoStore.findWhere('segmento_client_id', s.clientId))
        .map((e) => e.clientId)
        .toSet();
    final imagenIds = (await _imagenStore.findWhere('segmento_client_id', s.clientId))
        .map((e) => e.clientId)
        .toSet();
    final mensajeIds = (await _mensajeStore.findWhere('segmento_client_id', s.clientId))
        .map((e) => e.clientId)
        .toSet();

    final scopes = <(String, Set<String>)>[
      ('video', videoIds),
      ('imagen', imagenIds),
      ('mensaje', mensajeIds),
    ];

    var combined = segSummary;
    for (final (entityType, ids) in scopes) {
      if (ids.isEmpty) continue; // nada de este tipo para este segmento
      AppLog.i('ForzarEnvioController._sendOne(${s.id}): drenando "$entityType"...');
      final summary =
          await _engine.drain(entityType: entityType, onlyClientIds: ids);
      combined = _accumulate(combined, summary);
      if (summary.authExpired) return combined; // no purgar tras auth expirado
    }

    // Todo OK del segmento → sync-complete + borrado; algo pendiente → se queda.
    await _purge.purgeIfFullySynced(s);
    return combined;
  }

  /// Envío de UN segmento (botón "enviar").
  Future<void> enviarCloud(SegmentoEntity segmento) async {
    if (!_connectivity.isConnected) {
      lastError.value = 'No hay conexión a internet.';
      AppLog.w('ForzarEnvioController.enviarCloud: sin red, abortando.');
      return;
    }

    final displayId = segmento.id ?? -1;
    if (enviandoIds.contains(displayId)) return; // guard re-entrancia
    enviandoIds.add(displayId);
    lastError.value = '';
    lastDrainSummary.value = null;

    try {
      final summary = await _sendOne(segmento);
      lastDrainSummary.value = summary;
      if (summary.rejected > 0 || summary.conflicts > 0) {
        AppLog.w(
          'ForzarEnvioController.enviarCloud: '
          'rechazados=${summary.rejected} conflictos=${summary.conflicts}',
        );
      }
    } catch (e, st) {
      lastError.value = e.toString();
      AppLog.e('ForzarEnvioController.enviarCloud', error: e, stackTrace: st);
    } finally {
      enviandoIds.remove(displayId);
      await loadSegmentos();
    }
  }

  /// Envío de TODOS los segmentos pendientes, uno a uno (igual que pulsar
  /// "enviar" en cada uno). Un segmento pendiente = tiene algún dato/imagen/
  /// vídeo/mensaje sin subir. Nunca aborta por un fallo de un segmento; sí por
  /// sesión caducada. El GPS (batches) es global → se drena una vez al final.
  Future<void> enviarAllCloud() async {
    if (!_connectivity.isConnected) {
      lastError.value = 'No hay conexión a internet.';
      AppLog.w('ForzarEnvioController.enviarAllCloud: sin red, abortando.');
      return;
    }
    if (isEnviandoTodos.value) return;
    isEnviandoTodos.value = true;
    lastError.value = '';
    lastDrainSummary.value = null;

    try {
      // Segmentos pendientes: los que NO están totalmente sincronizados.
      final u = await _purge.readUnsyncedSets();
      final pending = <SegmentoEntity>[];
      for (final s in List.of(segmentos)) {
        final imgs =
            await _imagenStore.findWhere('segmento_client_id', s.clientId);
        final vids =
            await _videoStore.findWhere('segmento_client_id', s.clientId);
        final msgs =
            await _mensajeStore.findWhere('segmento_client_id', s.clientId);
        if (!PurgeSyncedSegmentoUseCase.isFullySynced(s, imgs, vids, msgs, u)) {
          pending.add(s);
        }
      }

      var combined = const DrainSummary();
      for (final s in pending) {
        final summary = await _sendOne(s);
        combined = _accumulate(combined, summary);
        if (summary.authExpired) {
          AppLog.w('ForzarEnvioController.enviarAllCloud: '
              'auth expirado, abortando.');
          break;
        }
      }

      // GPS es global (no per-segmento): drenar una vez al final.
      if (!combined.authExpired) {
        combined =
            _accumulate(combined, await _engine.drain(entityType: 'position'));
      }

      lastDrainSummary.value = combined;
      if (combined.rejected > 0 || combined.conflicts > 0) {
        AppLog.w(
          'ForzarEnvioController.enviarAllCloud: '
          'rechazados=${combined.rejected} conflictos=${combined.conflicts}',
        );
      }
    } catch (e, st) {
      lastError.value = e.toString();
      AppLog.e('ForzarEnvioController.enviarAllCloud', error: e, stackTrace: st);
    } finally {
      isEnviandoTodos.value = false;
      await loadSegmentos();
    }
  }
}
