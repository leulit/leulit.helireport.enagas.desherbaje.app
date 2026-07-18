import 'package:get/get.dart';
import 'package:helireport_desherbaje/core/my_getx_controller.dart';
import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';

import '../../core/app_di.dart';
import '../../core/app_log.dart';
import '../../core/result/data_result.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/sync/contracts/sync_job.dart';
import '../../core/sync/engine/sync_engine.dart';
import '../../core/sync/outbox/outbox_queue.dart';
import '../../data/sync/imagen_local_store.dart';
import '../../data/sync/mensaje_local_store.dart';
import '../../data/sync/propagate_segmento_remote_id_usecase.dart';
import '../../data/sync/purge_synced_segmento_usecase.dart';
import '../../data/sync/segmento_local_store.dart';
import '../../data/sync/video_local_store.dart';
import '../../domain/entities/segmento_entity.dart';
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
    PurgeSyncedSegmentoUseCase? purgeUseCase,
    ImagenLocalStore? imagenStore,
    VideoLocalStore? videoStore,
    MensajeLocalStore? mensajeStore,
    PropagateSegmentoRemoteIdUseCase? propagate,
    SegmentoLocalStore? segmentoStore,
    OutboxQueue? outbox,
  })  : _purge = purgeUseCase ?? PurgeSyncedSegmentoUseCase(),
        _imagenStore = imagenStore ?? DI.get<ImagenLocalStore>(),
        _videoStore = videoStore ?? DI.get<VideoLocalStore>(),
        _mensajeStore = mensajeStore ?? DI.get<MensajeLocalStore>(),
        _propagate = propagate ?? PropagateSegmentoRemoteIdUseCase(),
        _segmentoStore = segmentoStore ?? DI.get<SegmentoLocalStore>(),
        _outbox = outbox ?? AppDI.outboxQueue;

  final GetSegmentosUseCase _useCase;
  final SyncEngine _engine;
  final ConnectivityService _connectivity;
  final PurgeSyncedSegmentoUseCase _purge;
  final ImagenLocalStore _imagenStore;
  final VideoLocalStore _videoStore;
  final MensajeLocalStore _mensajeStore;
  final PropagateSegmentoRemoteIdUseCase _propagate;
  final SegmentoLocalStore _segmentoStore;
  final OutboxQueue _outbox;

  final segmentos = <SegmentoEntity>[].obs;
  final filtradas = <SegmentoEntity>[].obs;
  final isLoading = false.obs;
  final error = Rx<String?>(null);

  final selectedEstado = Rx<EstadoActividad?>(null);
  final selectedTipo = Rx<TipoActividad?>(null);
  final selectedCt = Rx<String?>(null);
  final filterDescripcion = ''.obs;

  final enviandoIds = <int>{}.obs;
  final isEnviandoTodos = false.obs;

  /// Último resumen de envío (subidos / reintentables / rechazados / conflictos).
  final lastDrainSummary = Rx<DrainSummary?>(null);

  /// Mensaje de error del último envío (vacío si no hubo error).
  final lastError = ''.obs;

  /// Segmentos del envío en curso cuyo contenido subió pero cuyo `sync-complete`
  /// no respondió 200 ([PurgeStatus.finalizeFailed]). No es un éxito: el backend
  /// mantiene sus filas `pending` hasta que el cierre se confirme. Se reporta en
  /// [lastError] para que el usuario distinga "enviado y confirmado" de "enviado
  /// sin confirmar".
  int _finalizeNoConfirmado = 0;

  @override
  void myOnInit() {
    debounce(
      filterDescripcion,
      (_) => _applyFilter(),
      time: const Duration(milliseconds: 300),
    );
    loadSegmentos();
  }

  /// Etiqueta legible del CT. El nombre viaja en la propia entidad (§3/§8);
  /// cae a 'CT desconocido' si viniera vacío.
  String ctLabel(String ctname) =>
      ctname.isNotEmpty ? ctname : 'CT desconocido';

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

  void filterByCt(String? ctname) {
    selectedCt.value = ctname;
    _applyFilter();
  }

  /// Nombres de CT presentes en los segmentos cargados, ordenados alfabéticamente.
  List<String> get ctsDisponibles {
    final names = segmentos.map((s) => s.ctname).toSet().toList();
    names.sort((a, b) => ctLabel(a).compareTo(ctLabel(b)));
    return names;
  }

  void _applyFilter() {
    final query = filterDescripcion.value.trim().toLowerCase();
    final estado = selectedEstado.value;
    final tipo = selectedTipo.value;
    final ct = selectedCt.value;

    filtradas.assignAll(segmentos.where((s) {
      if (estado != null && s.estado != estado) return false;
      if (tipo != null && s.tipoActividad != tipo) return false;
      if (ct != null && s.ctname != ct) return false;
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
  /// subirían sin vínculo si se enviaran antes. Si el upsert se entrega, se
  /// reencola el sobre entero (todos los hijos locales) y se descartan las
  /// sesiones de subida de vídeo antes de drenarlo: el backend anula el intento
  /// previo incompleto al recibirlo, filas y ficheros incluidos. Después:
  /// vídeos → fotos → mensajes. Solo los jobs de ESE segmento. Un fallo del
  /// segmento aborta sin tocar los hijos; un fallo de un hijo deja el segmento
  /// pendiente sin tocar a los demás segmentos.
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
    if (fresh == null || backendId == null) {
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

    // La unidad de sincronización es el SOBRE entero, no el adjunto suelto.
    // Un `upsert` entregado abre un intento nuevo en el backend y anula el
    // anterior incompleto: borra sus filas y ficheros `pending`. Si un hijo
    // sigue estando en local es que pertenece por definición a un sobre sin
    // cerrar —uno cerrado ya se habría purgado tras el 200 de sync-complete—,
    // así que hay que reenviarlo aunque su job figure ya como `synced`; si no,
    // el backend lo borró y nadie lo vuelve a subir (foto perdida en campo).
    // Solo cuando el upsert se entregó de verdad (`succeeded > 0`): sin upsert
    // no hay borrado remoto, y reencolar duplicaría lo ya subido (el dedup por
    // client_id ya no existe en la API).
    if (segSummary.succeeded > 0) {
      // §2 regla 2: el upsert entregado anula el intento anterior y borra sus
      // ficheros `pending`. Toda sesión de subida de vídeo guardada pertenece a
      // ese intento muerto; si no se descarta, el adapter reanudaría contra ella,
      // vería `complete: true` y daría éxito sin subir un solo byte — y el
      // sync-complete siguiente purgaría el vídeo local. Solo aquí: un reintento
      // de cierre (sin upsert entregado) no anula nada y no debe forzar resubidas.
      await _videoStore.clearUploadSessions(s.clientId);

      for (final (entityType, ids) in scopes) {
        for (final clientId in ids) {
          // Los tres adaptadores hijos solo aceptan `create`; reencolar el
          // mismo triple devuelve el job a `pending` conservando su remote_id.
          await _outbox.enqueue(
            entityType: entityType,
            clientId: clientId,
            operation: SyncOperation.create,
          );
        }
      }
      AppLog.i('ForzarEnvioController._sendOne(${s.id}): upsert entregado → '
          'reencolado el sobre completo (${videoIds.length} vídeos, '
          '${imagenIds.length} fotos, ${mensajeIds.length} mensajes).');
    }

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
    // Se pasa `fresh`, no `s`: en un segmento nuevo `s.id` sigue a null (la copia
    // en memoria es previa al upsert) y `purgeIfFullySynced` cortaría por
    // `skippedNoRemoteId`, así que el sync-complete NUNCA se dispararía en el
    // primer envío y sus filas quedarían `pending` en el backend (§2 regla 1: el
    // id definitivo es el que devuelve el upsert).
    final outcome = await _purge.purgeIfFullySynced(fresh);
    if (outcome.status == PurgeStatus.finalizeFailed) {
      // El contenido está en el backend pero sin el 200 de sync-complete sigue
      // marcado `pending` allí: no se purga nada (§2 regla 3) y hay que decirlo.
      _finalizeNoConfirmado++;
      AppLog.w('ForzarEnvioController._sendOne(${s.id}): contenido subido pero '
          'sync-complete no confirmó el cierre — se reintentará.');
    }
    return combined;
  }

  /// Traslada a [lastError] los cierres sin confirmar del envío en curso.
  /// Nunca pisa un error ya reportado (una excepción es más específica).
  void _reportFinalizeNoConfirmado() {
    if (_finalizeNoConfirmado == 0 || lastError.value.isNotEmpty) return;
    lastError.value = 'Contenido enviado, pero el servidor no confirmó el '
        'cierre de $_finalizeNoConfirmado segmento(s): siguen pendientes en la '
        'nube. Vuelve a enviarlos.';
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
    _finalizeNoConfirmado = 0;

    try {
      final summary = await _sendOne(segmento);
      lastDrainSummary.value = summary;
      _reportFinalizeNoConfirmado();
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
  /// vídeo/mensaje sin subir, o ya lo subió todo y solo le falta confirmar el
  /// cierre con el backend. Nunca aborta por un fallo de un segmento; sí por
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
    _finalizeNoConfirmado = 0;

    try {
      // Segmentos pendientes: los que NO están totalmente sincronizados, más
      // los que solo esperan el cierre (ver abajo).
      final u = await _purge.readUnsyncedSets();
      final pending = <SegmentoEntity>[];
      for (final s in List.of(segmentos)) {
        final imgs =
            await _imagenStore.findWhere('segmento_client_id', s.clientId);
        final vids =
            await _videoStore.findWhere('segmento_client_id', s.clientId);
        final msgs =
            await _mensajeStore.findWhere('segmento_client_id', s.clientId);
        final fullySynced =
            PurgeSyncedSegmentoUseCase.isFullySynced(s, imgs, vids, msgs, u);
        // Un segmento con id de backend y CERO jobs sin sincronizar que SIGUE en
        // local solo puede estar en `finalizeFailed`: el 200 de sync-complete lo
        // habría purgado (§2 regla 3). Excluirlo lo condena — "Enviar todos" no
        // volvería a tocarlo nunca, el backend dejaría sus filas `pending` para
        // siempre y el próximo upsert las borraría. sync-complete es idempotente
        // y no destructivo (§7): reintentar el cierre siempre es seguro, y con el
        // upsert ya `synced` el drain no entrega nada (succeeded == 0), así que
        // no se anula ningún intento ni se resube un solo byte.
        if (!fullySynced || s.id != null) pending.add(s);
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
      _reportFinalizeNoConfirmado();
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
