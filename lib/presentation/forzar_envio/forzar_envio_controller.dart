import 'dart:async';

import 'package:get/get.dart';
import 'package:helireport_desherbaje/core/my_getx_controller.dart';
import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';

import '../../core/app_di.dart';
import '../../core/app_log.dart';
import '../../core/app_typed_actions.dart';
import '../../core/result/data_result.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/sync/contracts/sync_job.dart';
import '../../core/sync/engine/sync_engine.dart';
import '../../core/sync/outbox/outbox_queue.dart';
import '../../core/sync/contracts/sync_progress.dart';
import '../../core/sync/pull/cancel_token.dart';
import '../../core/sync/sync_actions.dart';
import '../../data/sync/imagen_local_store.dart';
import '../../data/sync/mensaje_local_store.dart';
import '../../data/sync/propagate_segmento_remote_id_usecase.dart';
import '../../data/sync/purge_synced_segmento_usecase.dart';
import '../../data/sync/segmento_local_store.dart';
import '../../data/sync/traza_local_store.dart';
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
    TrazaLocalStore? trazaStore,
  })  : _purge = purgeUseCase ?? PurgeSyncedSegmentoUseCase(),
        _imagenStore = imagenStore ?? DI.get<ImagenLocalStore>(),
        _videoStore = videoStore ?? DI.get<VideoLocalStore>(),
        _mensajeStore = mensajeStore ?? DI.get<MensajeLocalStore>(),
        _propagate = propagate ?? PropagateSegmentoRemoteIdUseCase(),
        _segmentoStore = segmentoStore ?? DI.get<SegmentoLocalStore>(),
        _outbox = outbox ?? AppDI.outboxQueue,
        _trazaStore = trazaStore ?? DI.get<TrazaLocalStore>();

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
  final TrazaLocalStore _trazaStore;

  final segmentos = <SegmentoEntity>[].obs;
  final filtradas = <SegmentoEntity>[].obs;
  final isLoading = false.obs;
  final error = Rx<String?>(null);

  final selectedEstado = Rx<EstadoActividad?>(null);
  final selectedTipo = Rx<TipoActividad?>(null);
  final selectedCt = Rx<String?>(null);
  final filterDescripcion = ''.obs;

  /// Envíos en curso, por `clientId`. NO por `id` remoto: es null hasta el
  /// primer upsert, así que todo segmento nuevo colisionaría en la misma clave.
  final enviandoIds = <String>{}.obs;
  final isEnviandoTodos = false.obs;

  /// El usuario pulsó "Cancelar" y el envío aún no se ha detenido. La
  /// cancelación es cooperativa (hasta ~un chunk de vídeo de retardo), así que
  /// hace falta un tercer estado: sin él, la UI volvería a "Enviar" mientras
  /// todavía salen bytes y un segundo toque solaparía envíos.
  final isCancelando = false.obs;

  /// Token del envío en curso. Uno solo: "enviar" y "enviar todos" son
  /// mutuamente excluyentes (ambos comprueban el otro antes de arrancar).
  CancelToken? _token;

  /// Progreso legible del envío en curso ("Enviando 2 de 7 · descripción").
  /// Vacío cuando no hay envío. El botón ya no puede alojar el spinner —ese
  /// sitio lo ocupa "Cancelar"—, así que el feedback de "está pasando algo"
  /// vive aquí y en la barra que lo acompaña.
  final progresoEnvio = ''.obs;

  /// Fracción 0..1 de la subida en curso, o `null` = indeterminado. Solo los
  /// adaptadores con bucle largo (vídeo) la rellenan; el resto de jobs son una
  /// petición y no tienen nada que reportar.
  final progresoFraccion = Rxn<double>();

  /// Sumidero que se pasa a `drain`. Se limpia al terminar cada drain para que
  /// la barra no se quede clavada al 100 % del vídeo anterior mientras suben
  /// fotos o mensajes.
  void _onProgresoBytes(SyncProgress p) => progresoFraccion.value = p.fraction;

  void _publicarProgreso(int indice, int total, SegmentoEntity s) {
    final desc = s.descripcion.trim();
    progresoEnvio.value = desc.isEmpty
        ? 'Enviando $indice de $total'
        : 'Enviando $indice de $total · $desc';
  }

  /// Hay un envío vivo (individual o masivo). La vista lo usa para ocultar la
  /// navegación y desactivar el resto de botones.
  bool get isEnviando => isEnviandoTodos.value || enviandoIds.isNotEmpty;

  /// Corta el envío en curso. No deshace nada: lo ya subido sigue subido y lo
  /// que quedaba sigue pendiente en el móvil. El vídeo a medias se reanuda
  /// desde el offset del servidor en el siguiente envío.
  void cancelarEnvio() {
    final token = _token;
    if (token == null || token.isCancelled) return;
    isCancelando.value = true;
    token.cancel();
    AppLog.i('ForzarEnvioController: envío cancelado por el usuario.');
  }

  /// Último resumen de envío (subidos / reintentables / rechazados / conflictos).
  final lastDrainSummary = Rx<DrainSummary?>(null);

  /// Mensaje de error del último envío (vacío si no hubo error).
  final lastError = ''.obs;

  /// Mensaje informativo del último envío cuando NO hubo error: confirmación de
  /// subida o "no había nada pendiente". Separado de [lastError] para que la
  /// vista pueda distinguir éxito de fallo sin parsear texto.
  final lastInfo = ''.obs;

  /// Rechazos recibidos del motor durante el envío en curso. Traen el motivo
  /// real del backend ([EntityRejectedEvent.errorMessageEs] + `statusCode`),
  /// que el `DrainSummary` reduce a un simple contador.
  final rechazos = <EntityRejectedEvent>[].obs;

  /// Jobs del sobre que SIGUEN en `rejected` tras el envío, por tipo de
  /// entidad. Un job rechazado es invisible para el drain pero cuenta como
  /// no-sincronizado para la purga: sin reportarlo, el segmento queda
  /// bloqueado en silencio.
  final Map<String, int> _bloqueados = <String, int>{};

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
    // El motor emite un rechazo por job desde `DispatchActionTask`. El
    // `DrainSummary` solo cuenta; el motivo legible viaja aquí.
    onTypedAction<EntityRejectedEvent>(
      SyncActions.entityRejected,
      (event) {
        final data = event.data;
        if (data != null) rechazos.add(data);
      },
      debugLabel: 'ForzarEnvio.entityRejected',
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
          data.where((s) => [
                EstadoActividad.finalizada,
                EstadoActividad.contratista
              ].contains(s.estado)),
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
        cancelled: a.cancelled || b.cancelled,
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
    // Hijos del sobre. Se enumeran ANTES del drain porque sus `clientId` hacen
    // falta ya para desatascar los jobs `rejected`. `propagate` (más abajo)
    // solo reescribe `segmento_id` de estas filas, nunca su `clientId`, así que
    // la lista sigue siendo válida después: no hace falta releerla.
    final videoIds =
        (await _videoStore.findWhere('segmento_client_id', s.clientId))
            .map((e) => e.clientId)
            .toSet();
    final imagenIds =
        (await _imagenStore.findWhere('segmento_client_id', s.clientId))
            .map((e) => e.clientId)
            .toSet();
    final mensajeIds =
        (await _mensajeStore.findWhere('segmento_client_id', s.clientId))
            .map((e) => e.clientId)
            .toSet();

    final scopes = <(String, Set<String>)>[
      ('video', videoIds),
      ('imagen', imagenIds),
      ('mensaje', mensajeIds),
    ];

    await _desatascarRechazados(s, scopes);

    final summary = await _drenarSobre(s, scopes);

    // Sin caminos silenciosos: si algo del sobre volvió a `rejected` (o nunca
    // salió de ahí), se contabiliza para reportarlo al usuario. Se hace aquí y
    // no dentro de `_drenarSobre` porque ese método tiene salidas tempranas.
    final bloqueos = await _contarRechazadosDelSobre(s, scopes);
    bloqueos
        .forEach((tipo, n) => _bloqueados[tipo] = (_bloqueados[tipo] ?? 0) + n);

    return summary;
  }

  /// Devuelve a `pending` los jobs de ESTE sobre atascados en `rejected`.
  ///
  /// `OutboxQueue.nextPending` filtra por `status='pending'`, así que el drain
  /// nunca vuelve a tocar un job rechazado; pero `readUnsyncedSets` sí lo
  /// cuenta, de modo que la purga tampoco cierra el segmento. Resultado: sobre
  /// bloqueado para siempre y en silencio. Reencolar el mismo triple
  /// `(entity_type, client_id, operation)` lo devuelve a `pending` conservando
  /// su `remote_id` (`ON CONFLICT` de [OutboxQueue.enqueue]).
  ///
  /// Reintento MANUAL: UNA pasada por pulsación del usuario. Si vuelve a
  /// fallar, el job queda otra vez en `rejected` y se reporta el motivo. Sin
  /// timers, sin backoff, sin reintentos en cadena.
  Future<void> _desatascarRechazados(
    SegmentoEntity s,
    List<(String, Set<String>)> scopes,
  ) async {
    for (final (entityType, ids) in _ambitosDelSobre(s, scopes)) {
      final propios = await _rechazadosDe(entityType, ids);
      if (propios.isEmpty) continue;
      for (final job in propios) {
        await _outbox.enqueue(
          entityType: entityType,
          clientId: job.clientId,
          operation: job.operation,
        );
      }
      AppLog.w('ForzarEnvioController._sendOne(${s.id}): desatascados '
          '${propios.length} job(s) "$entityType" de rejected → pending.');
    }
  }

  /// Jobs del sobre que siguen en `rejected`, contados por tipo de entidad.
  Future<Map<String, int>> _contarRechazadosDelSobre(
    SegmentoEntity s,
    List<(String, Set<String>)> scopes,
  ) async {
    final out = <String, int>{};
    for (final (entityType, ids) in _ambitosDelSobre(s, scopes)) {
      final propios = await _rechazadosDe(entityType, ids);
      if (propios.isNotEmpty) out[entityType] = propios.length;
    }
    return out;
  }

  /// Ámbitos del sobre: el propio segmento más sus hijos. Los tipos sin hijos
  /// se omiten — un `ids` vacío no acota nada y tocaría jobs ajenos.
  List<(String, Set<String>)> _ambitosDelSobre(
    SegmentoEntity s,
    List<(String, Set<String>)> scopes,
  ) =>
      [
        ('segmento', {s.clientId}),
        ...scopes.where((e) => e.$2.isNotEmpty),
      ];

  /// Jobs `rejected` de [entityType] cuyo `clientId` pertenece al sobre. El
  /// filtro es innegociable: jamás se tocan jobs de otros segmentos.
  Future<List<SyncJob>> _rechazadosDe(
    String entityType,
    Set<String> ids,
  ) async {
    final rejected = await _outbox.rejectedJobs(entityType: entityType);
    return rejected.where((j) => ids.contains(j.clientId)).toList();
  }

  /// Drenado del sobre: segmento (upsert) → propagación de id → hijos → purga.
  Future<DrainSummary> _drenarSobre(
    SegmentoEntity s,
    List<(String, Set<String>)> scopes,
  ) async {
    AppLog.i('ForzarEnvioController._sendOne(${s.id}): drenando "segmento"...');
    final segSummary = await _engine.drain(
      entityType: 'segmento',
      onlyClientIds: {s.clientId},
      token: _token,
    );
    progresoFraccion.value = null;

    if (segSummary.cancelled) return segSummary;

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
      final resumen = scopes.map((e) => '${e.$2.length} ${e.$1}').join(', ');
      AppLog.i('ForzarEnvioController._sendOne(${s.id}): upsert entregado → '
          'reencolado el sobre completo ($resumen).');
    }

    var combined = segSummary;
    for (final (entityType, ids) in scopes) {
      if (ids.isEmpty) continue; // nada de este tipo para este segmento
      AppLog.i(
          'ForzarEnvioController._sendOne(${s.id}): drenando "$entityType"...');
      final summary = await _engine.drain(
        entityType: entityType,
        onlyClientIds: ids,
        token: _token,
        onProgress: _onProgresoBytes,
      );
      progresoFraccion.value = null;
      combined = _accumulate(combined, summary);
      if (summary.authExpired) return combined; // no purgar tras auth expirado
      // Cancelado con hijos aún por drenar: el sobre no está completo, así que
      // no hay nada que cerrar. Si la cancelación llega DESPUÉS de este bucle,
      // se deja completar el sync-complete (abajo): los bytes ya están arriba y
      // abortar el cierre dejaría sus filas `pending` en el backend para nada.
      if (summary.cancelled) return combined;
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

  /// Nombre en plural y en castellano de cada tipo de entidad, para mensajes
  /// dirigidos a un operador de campo (no ve "imagen"/"video", ve "fotos").
  static const Map<String, String> _etiquetasTipo = {
    'segmento': 'datos del segmento',
    'video': 'vídeos',
    'imagen': 'fotos',
    'mensaje': 'mensajes',
  };

  /// Cierra el aviso de resultado (botón de la vista). No cancela ni deshace
  /// nada: el estado real vive en el outbox, esto solo oculta el banner.
  void descartarResultado() {
    lastError.value = '';
    lastInfo.value = '';
    lastDrainSummary.value = null;
    rechazos.clear();
  }

  /// Estado inicial de cada envío. Sin esto, los rechazos y bloqueos de un
  /// envío anterior contaminarían el siguiente.
  void _resetResultado() {
    lastError.value = '';
    lastInfo.value = '';
    lastDrainSummary.value = null;
    rechazos.clear();
    _bloqueados.clear();
    _finalizeNoConfirmado = 0;
  }

  /// Cierra el envío dejando SIEMPRE un resultado legible: error, bloqueo,
  /// cierre sin confirmar, o confirmación explícita. Un envío que no sube nada
  /// no puede terminar indistinguible de uno correcto.
  ///
  /// [lastError] ya puede traer una excepción capturada; es más específica que
  /// cualquier resumen, así que nunca se pisa.
  void _reportarResultado(DrainSummary summary) {
    if (lastError.value.isEmpty && _bloqueados.isNotEmpty) {
      final detalle = _bloqueados.entries
          .map((e) => '${e.value} ${_etiquetasTipo[e.key] ?? e.key}')
          .join(', ');
      lastError.value = 'No se ha podido subir parte del contenido ($detalle). '
          'Sigue guardado en el móvil: revisa el motivo y vuelve a intentarlo.';
    }

    if (lastError.value.isEmpty && _finalizeNoConfirmado > 0) {
      lastError.value = 'Contenido enviado, pero el servidor no confirmó el '
          'cierre de $_finalizeNoConfirmado segmento(s): siguen pendientes en la '
          'nube. Vuelve a enviarlos.';
    }

    if (lastError.value.isNotEmpty) return;

    // Cancelado a mano ≠ terminado. Se reporta como aviso (no error): nada se
    // ha perdido, pero decir "envío completado" sería mentir.
    if (summary.cancelled) {
      lastInfo.value = 'Envío cancelado: ${summary.succeeded} elemento(s) '
          'subidos. El resto sigue guardado en el móvil.';
      return;
    }

    lastInfo.value = summary.succeeded > 0
        ? 'Envío completado: ${summary.succeeded} elemento(s) subidos a la nube.'
        : 'No había nada pendiente de enviar: ya estaba todo sincronizado.';
  }

  /// Mensaje mostrado cuando un envío se aborta por haber una traza GPS en
  /// grabación en curso (ver [_trazaEnGrabacion]).
  static const _mensajeTrazaEnGrabacion =
      'Hay una traza en grabación: finalízala antes de enviar.';

  /// Envío bloqueado mientras hay una traza en grabación: sus puntos siguen
  /// acumulándose en memoria y no forman parte de ningún job del outbox
  /// todavía, así que enviar "ahora" nunca los incluiría — mejor esperar a
  /// que el usuario finalice para no dar una falsa sensación de "todo subido".
  Future<bool> _trazaEnGrabacion() => AppTypedActions.isTrazaRecording();

  /// Envío de UN segmento (botón "enviar").
  Future<void> enviarCloud(SegmentoEntity segmento) async {
    _resetResultado();
    if (!_connectivity.isConnected) {
      lastError.value = 'No hay conexión a internet.';
      AppLog.w('ForzarEnvioController.enviarCloud: sin red, abortando.');
      return;
    }
    if (await _trazaEnGrabacion()) {
      lastError.value = _mensajeTrazaEnGrabacion;
      AppLog.w(
          'ForzarEnvioController.enviarCloud: traza en grabación, abortando.');
      return;
    }

    final key = segmento.clientId;
    if (enviandoIds.contains(key)) return; // guard re-entrancia
    if (isEnviandoTodos.value) return; // envío masivo en curso
    enviandoIds.add(key);
    _token = CancelToken();
    _publicarProgreso(1, 1, segmento);

    try {
      final summary = await _sendOne(segmento);
      lastDrainSummary.value = summary;
      _reportarResultado(summary);
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
      _token = null;
      isCancelando.value = false;
      progresoEnvio.value = '';
      progresoFraccion.value = null;
      enviandoIds.remove(key);
      await loadSegmentos();
    }
  }

  /// Envío de TODOS los segmentos pendientes, uno a uno (igual que pulsar
  /// "enviar" en cada uno). Un segmento pendiente = tiene algún dato/imagen/
  /// vídeo/mensaje sin subir, o ya lo subió todo y solo le falta confirmar el
  /// cierre con el backend. Nunca aborta por un fallo de un segmento; sí por
  /// sesión caducada. El GPS (batches) es global → se drena una vez al final.
  Future<void> enviarAllCloud() async {
    _resetResultado();
    if (!_connectivity.isConnected) {
      lastError.value = 'No hay conexión a internet.';
      AppLog.w('ForzarEnvioController.enviarAllCloud: sin red, abortando.');
      return;
    }
    if (await _trazaEnGrabacion()) {
      lastError.value = _mensajeTrazaEnGrabacion;
      AppLog.w(
          'ForzarEnvioController.enviarAllCloud: traza en grabación, abortando.');
      return;
    }
    if (isEnviandoTodos.value) return;
    if (enviandoIds.isNotEmpty) return; // envío individual en curso
    isEnviandoTodos.value = true;
    _token = CancelToken();

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
      for (var i = 0; i < pending.length; i++) {
        final s = pending[i];
        // Corte entre sobres: el que ya empezó decide él mismo dónde parar
        // (`_drenarSobre`); aquí solo se evita arrancar el siguiente.
        if (_token?.isCancelled ?? false) {
          combined = combined.copyWith(cancelled: true);
          break;
        }
        _publicarProgreso(i + 1, pending.length, s);
        final summary = await _sendOne(s);
        combined = _accumulate(combined, summary);
        if (summary.cancelled) break;
        if (summary.authExpired) {
          AppLog.w('ForzarEnvioController.enviarAllCloud: '
              'auth expirado, abortando.');
          break;
        }
      }

      // GPS es global (no per-segmento): drenar una vez al final. El tipo
      // registrado es 'traza' (antes 'position', que nunca existió como
      // entidad — el GPS jamás se enviaba desde esta pantalla).
      if (!combined.authExpired && !combined.cancelled) {
        final trazaSummary = await _engine.drain(
          entityType: 'traza',
          token: _token,
        );
        combined = _accumulate(combined, trazaSummary);
        // Se purgan las trazas ya subidas incluso si hubo rechazos en esta
        // pasada: `deleteSynced` solo toca filas con `synced_at` puesto por un
        // envío anterior (o por este mismo), nunca las que siguen pendientes.
        await _trazaStore.deleteSynced();
      }

      lastDrainSummary.value = combined;
      _reportarResultado(combined);
      if (combined.rejected > 0 || combined.conflicts > 0) {
        AppLog.w(
          'ForzarEnvioController.enviarAllCloud: '
          'rechazados=${combined.rejected} conflictos=${combined.conflicts}',
        );
      }
    } catch (e, st) {
      lastError.value = e.toString();
      AppLog.e('ForzarEnvioController.enviarAllCloud',
          error: e, stackTrace: st);
    } finally {
      _token = null;
      isCancelando.value = false;
      progresoEnvio.value = '';
      progresoFraccion.value = null;
      isEnviandoTodos.value = false;
      await loadSegmentos();
    }
  }
}
