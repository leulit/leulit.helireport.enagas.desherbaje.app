import 'dart:async';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_di.dart';
import '../../core/app_log.dart';
import '../../core/app_router.dart';
import '../../core/my_getx_controller.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/gasoductos_service.dart';
import '../../core/services/master_data_load_result.dart';
import '../../core/services/pks_service.dart';
import '../../core/services/hitos_service.dart';
import '../../core/widgets/orto_tile_layers.dart';

import '../../core/sync/sync.dart';
import '../../data/repository/auth_repository_impl.dart';
import '../../domain/entities/user_role.dart';
import '../../domain/repository/auth_repository.dart';
import 'sync_models.dart';

/// Controlador de la página de sincronización. Tras el cambio de alcance
/// (abril 2026), la página solo sirve para **descargar datos maestros**:
/// usuario, gasoductos, PKs y posiciones fijas. Nada de subidas, conflictos
/// ni "Preparar trabajo de campo".
class SincronizacionController extends MyGetxController {
  SincronizacionController({
    AuthRepository? authRepository,
    GasoductosService? gasoductosService,
    PksService? pksService,
    HitosService? hitosService,
    ConnectivityService? connectivity,
  })  : _auth = authRepository ?? AuthRepositoryImpl(),
        _gasoductos = gasoductosService ?? AppDI.gasoductosService,
        _pks = pksService ?? AppDI.pksService,
        _hitos = hitosService ?? AppDI.hitosService,
        _connectivity = connectivity ?? AppDI.connectivityService;

  static const String lastDownloadPrefix = 'sync_master_last_download_';

  final AuthRepository _auth;
  final GasoductosService _gasoductos;
  final PksService _pks;
  final HitosService _hitos;
  final ConnectivityService _connectivity;

  // ─────────────────────────────── State ───────────────────────────────

  final isOnline = true.obs;
  final isWorking = false.obs;
  final lastError = Rxn<String>();

  /// Fila por cada [MasterDataKind] — orden estable.
  final rows = <MasterDataRow>[].obs;

  /// Rol del usuario logueado, para gatear el botón "Reset" (solo
  /// [UserRole.superadmin]). `null` mientras se resuelve o si no hay sesión.
  final userRole = Rx<UserRole?>(null);
  bool get isSuperadmin => userRole.value == UserRole.superadmin;

  CancelToken? _activeToken;

  // ─────────────────────────────── Lifecycle ───────────────────────────

  @override
  void myOnInit() {
    isOnline.value = _connectivity.isConnected;
    onTypedAction(
      SyncActions.connectionRestored,
      (_) => isOnline.value = true,
      debugLabel: 'Sync.connRestored',
    );
    onTypedAction(
      SyncActions.connectionLost,
      (_) => isOnline.value = false,
      debugLabel: 'Sync.connLost',
    );
    _initRows();
    unawaited(_loadUserRole());
  }

  /// Resuelve el rol en segundo plano. Si la lectura de sesión falla, el rol
  /// queda `null` y el botón destructivo NO se pinta: ante duda sobre quién
  /// está delante, se oculta. El fallo se loguea, no se traga.
  Future<void> _loadUserRole() async {
    try {
      final user = await _auth.getCurrentUser();
      userRole.value = user?.role;
    } catch (e, st) {
      userRole.value = null;
      AppLog.w('SincronizacionController._loadUserRole: $e', stackTrace: st);
    }
  }

  /// Solo [UserRole.superadmin]: borra el contenido de TODAS las tablas
  /// locales (entidades + `sync_queue`/`sync_conflicts`/`pull_state`/versión
  /// de esquema), dejando la base de datos como recién instalada, y cierra
  /// sesión. No toca ficheros de fotos/vídeos en disco — viven en la galería
  /// del dispositivo, que es su copia de seguridad.
  ///
  /// Destructivo e irreversible: el trabajo de campo aún no enviado (fotos,
  /// vídeos, segmentos, trazas) se pierde para siempre. La confirmación vive
  /// en la vista; este método asume que ya se confirmó.
  Future<void> resetAppData() async {
    await OfflineDatabase.wipeAll(AppDI.database);
    // Las fechas de "última descarga" viven en SharedPreferences, no en la BD:
    // sin borrarlas, tras el reset cada fila seguiría mostrando una descarga
    // que ya no existe en local.
    await _clearLastDownloads();
    // La caché de tiles de mapa vive en el directorio de caché del SO, fuera
    // de la BD: el Reset debe enumerar TODOS los almacenes, no solo SQLite.
    await resetMapTileCache();
    AppDI.sessionState.set(false);
    Get.offAllNamed(AppRoutes.login);
  }

  Future<void> _clearLastDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    for (final kind in MasterDataKind.values) {
      await prefs.remove('$lastDownloadPrefix${kind.name}');
    }
    rows.assignAll(
      MasterDataKind.values.map((k) => MasterDataRow(kind: k)),
    );
  }

  Future<void> _initRows() async {
    final prefs = await SharedPreferences.getInstance();
    rows.assignAll(MasterDataKind.values.map((k) {
      final last = prefs.getString('$lastDownloadPrefix${k.name}');
      return MasterDataRow(
        kind: k,
        status: MasterDataStatus.idle,
        lastDownloadAt: last == null ? null : DateTime.tryParse(last),
      );
    }));
  }

  // ─────────────────────────────── Actions ─────────────────────────────

  /// Descarga todas las filas disponibles (omite las marcadas como
  /// `unavailable`). Cooperativamente cancelable.
  Future<void> descargarTodo() async {
    if (isWorking.value) return;
    // NF-15: guard — rows may be empty if _initRows hasn't resolved yet.
    if (rows.isEmpty) return;
    if (!_connectivity.isConnected) {
      lastError.value = 'No hay conexión a internet.';
      return;
    }
    isWorking.value = true;
    lastError.value = null;
    _activeToken = CancelToken();
    try {
      for (final kind in MasterDataKind.values) {
        if (_activeToken?.isCancelled ?? false) break;
        if (_rowFor(kind).status == MasterDataStatus.unavailable) continue;
        await _runOne(kind, sharedToken: _activeToken);
      }
    } finally {
      _activeToken = null;
      isWorking.value = false;
    }
  }

  /// Descarga una única fila.
  Future<void> descargar(MasterDataKind kind) async {
    if (isWorking.value) return;
    // NF-15: guard — rows may be empty if _initRows hasn't resolved yet.
    if (rows.isEmpty) return;
    if (_rowFor(kind).status == MasterDataStatus.unavailable) return;
    if (!_connectivity.isConnected) {
      lastError.value = 'No hay conexión a internet.';
      return;
    }
    isWorking.value = true;
    lastError.value = null;
    _activeToken = CancelToken();
    try {
      await _runOne(kind, sharedToken: _activeToken);
    } finally {
      _activeToken = null;
      isWorking.value = false;
    }
  }

  void cancelar() {
    _activeToken?.cancel();
  }

  /// Vuelve al login. Se llama desde el botón back del AppBar — el flujo de
  /// inicio no deja nada en el stack, así que `Get.back()` no funciona aquí.
  void volver() {
    if (isWorking.value) return;
    AppDI.sessionState.set(false);
    Get.offAllNamed(AppRoutes.login);
  }

  // ─────────────────────────── Internals ───────────────────────────────

  // NF-15: orElse guard prevents StateError when rows haven't been initialised.
  MasterDataRow _rowFor(MasterDataKind kind) =>
      rows.firstWhere((r) => r.kind == kind,
          orElse: () => MasterDataRow(kind: kind));

  void _updateRow(MasterDataKind kind, MasterDataRow updated) {
    final idx = rows.indexWhere((r) => r.kind == kind);
    if (idx == -1) return;
    rows[idx] = updated;
  }

  Future<void> _runOne(
    MasterDataKind kind, {
    required CancelToken? sharedToken,
  }) async {
    final current = _rowFor(kind);
    _updateRow(
      kind,
      current.copyWith(
        status: MasterDataStatus.downloading,
        clearError: true,
        clearProgress: true,
        clearProgressLabel: true,
        clearWarning: true,
      ),
    );

    // Aviso no bloqueante que se adjunta a la fila `success` al final (solo lo
    // fija la rama de segmentos cuando hay cambios locales pendientes).
    String? warning;
    final List<Worker> downloadWorkers = <Worker>[];
    try {
      if (sharedToken?.isCancelled ?? false) {
        _updateRow(
          kind,
          _rowFor(kind).copyWith(
            status: MasterDataStatus.idle,
            clearProgress: true,
            clearProgressLabel: true,
          ),
        );
        return;
      }
      MasterDataLoadResult? masterDataResult;
      switch (kind) {
        case MasterDataKind.user:
          await _auth.refreshUserData();
        case MasterDataKind.gasoductos:
          downloadWorkers.addAll(
            _attachProgressWorkers(
              kind: kind,
              total: _gasoductos.totalFiles,
              processed: _gasoductos.processedFiles,
            ),
          );
          // NF-12: reload now propagates on error; catch at _runOne level handles it.
          masterDataResult = await _gasoductos.reload(token: sharedToken);
        case MasterDataKind.pks:
          // TODO: Igualar la API de [PksService] con [GasoductosService] si
          // se desea mostrar progreso real distinto al ratio de ficheros.
          downloadWorkers.addAll(
            _attachProgressWorkers(
              kind: kind,
              total: _pks.totalFiles,
              processed: _pks.processedFiles,
            ),
          );
          // NF-12: reload now propagates on error; catch at _runOne level handles it.
          masterDataResult = await _pks.reload(token: sharedToken);
        case MasterDataKind.hitos:
          downloadWorkers.addAll(
            _attachProgressWorkers(
              kind: kind,
              total: _hitos.totalFiles,
              processed: _hitos.processedFiles,
            ),
          );
          masterDataResult = await _hitos.reload(token: sharedToken);
        case MasterDataKind.segmentos:
          // La descarga es ADD-ONLY (el fetcher nunca pisa filas locales), así
          // que ya no se aborta por cambios pendientes: se descargan los
          // segmentos nuevos y se avisa de forma no bloqueante si hay locales
          // sin subir.
          final int pending = await _countPendingForSegmentos();
          if (pending > 0) {
            warning =
                'Hay $pending cambios pendientes de subir. Súbelos antes de descargar la lista actualizada.';
          }
          final PullSummary? summary = await OfflineModule.runPull(
            'segmento',
            token: sharedToken,
            onProgress: (p) {
              final row = _rowFor(kind);
              _updateRow(
                kind,
                row.copyWith(
                  progress: p.fraction,
                  progressLabel: p.phase,
                  clearProgress: p.fraction == null,
                ),
              );
            },
          );
          if (summary == null) {
            throw StateError("Pull no disponible para 'segmento'");
          }
          if (summary.cancelled) {
            _updateRow(
              kind,
              _rowFor(kind).copyWith(
                status: MasterDataStatus.idle,
                clearProgress: true,
                clearProgressLabel: true,
              ),
            );
            return;
          }
          if (summary.authExpired) {
            _updateRow(
              kind,
              _rowFor(kind).copyWith(
                status: MasterDataStatus.error,
                errorMessage: 'La sesión ha caducado. Vuelve a iniciar sesión.',
                clearProgress: true,
                clearProgressLabel: true,
              ),
            );
            return;
          }
          // NF-1/NF-2/NF-3: degraded pull (blocking error or partial item
          // failures). Show an error row and skip the success timestamp so a
          // failed pull is never recorded as a successful one.
          if (summary.isDegraded) {
            final msg = summary.errorMessage ??
                (summary.outcome == PullOutcome.partial
                    ? 'Descarga parcial: algunos registros no se pudieron guardar.'
                    : 'Error durante la descarga de segmentos.');
            _updateRow(
              kind,
              _rowFor(kind).copyWith(
                status: MasterDataStatus.error,
                errorMessage: msg,
                clearProgress: true,
                clearProgressLabel: true,
              ),
            );
            return;
          }
        case MasterDataKind.posicionesFijas:
          final PullSummary? posicionesSummary = await OfflineModule.runPull(
            'posicion_fija',
            token: sharedToken,
            onProgress: (p) {
              final row = _rowFor(kind);
              _updateRow(
                kind,
                row.copyWith(
                  progress: p.fraction,
                  progressLabel: p.phase,
                  clearProgress: p.fraction == null,
                ),
              );
            },
          );
          if (posicionesSummary == null) {
            throw StateError("Pull no disponible para 'posicion_fija'");
          }
          if (posicionesSummary.cancelled) {
            _updateRow(
              kind,
              _rowFor(kind).copyWith(
                status: MasterDataStatus.idle,
                clearProgress: true,
                clearProgressLabel: true,
              ),
            );
            return;
          }
          if (posicionesSummary.authExpired) {
            _updateRow(
              kind,
              _rowFor(kind).copyWith(
                status: MasterDataStatus.error,
                errorMessage: 'La sesión ha caducado. Vuelve a iniciar sesión.',
                clearProgress: true,
                clearProgressLabel: true,
              ),
            );
            return;
          }
          if (posicionesSummary.isDegraded) {
            final msg = posicionesSummary.errorMessage ??
                (posicionesSummary.outcome == PullOutcome.partial
                    ? 'Descarga parcial: algunas posiciones fijas no se pudieron guardar.'
                    : 'Error durante la descarga de posiciones fijas.');
            _updateRow(
              kind,
              _rowFor(kind).copyWith(
                status: MasterDataStatus.error,
                errorMessage: msg,
                clearProgress: true,
                clearProgressLabel: true,
              ),
            );
            return;
          }
      }

      // NF-14: only persist lastDownloadAt when data came from the network.
      // Cache hits do NOT count as a fresh download.
      final servedFromCache =
          masterDataResult?.source == MasterDataSource.cache;
      final now = DateTime.now();
      if (!servedFromCache) {
        await _persistLastDownload(kind, now);
      }
      _updateRow(
        kind,
        _rowFor(kind).copyWith(
          status: MasterDataStatus.success,
          lastDownloadAt: servedFromCache ? null : now,
          servedFromCache: servedFromCache,
          warningMessage: warning,
          clearError: true,
          clearProgress: true,
          clearProgressLabel: true,
          clearWarning: warning == null,
        ),
      );
    } catch (e) {
      final msg = e.toString();
      lastError.value = msg;
      _updateRow(
        kind,
        _rowFor(kind).copyWith(
          status: MasterDataStatus.error,
          errorMessage: msg,
          clearProgress: true,
          clearProgressLabel: true,
        ),
      );
    } finally {
      for (final w in downloadWorkers) {
        w.dispose();
      }
    }
  }

  /// Conecta los observables `total` y `processed` de un servicio con la fila
  /// `kind`. Devuelve los workers para que el llamante pueda disponerlos al
  /// terminar la descarga (no se pasan a [addWorker] porque su ciclo de vida
  /// es por-descarga, no por-controller).
  List<Worker> _attachProgressWorkers({
    required MasterDataKind kind,
    required RxInt total,
    required RxInt processed,
  }) {
    void publish() {
      final t = total.value;
      final p = processed.value;
      final ratio = t > 0 ? (p / t).clamp(0.0, 1.0) : null;
      final label = t > 0 ? 'Descargando $p / $t archivos…' : null;
      final row = _rowFor(kind);
      _updateRow(
        kind,
        row.copyWith(
          progress: ratio,
          progressLabel: label,
          clearProgress: ratio == null,
          clearProgressLabel: label == null,
        ),
      );
    }

    return <Worker>[
      ever<int>(total, (_) => publish()),
      ever<int>(processed, (_) => publish()),
    ];
  }

  /// Suma los pendientes del outbox de los tres dominios vinculados a un
  /// segmento. Si cualquiera tiene pendientes, no se debe pisar la cache local
  /// con un pull remoto.
  Future<int> _countPendingForSegmentos() async {
    final OutboxQueue outbox = AppDI.outboxQueue;
    final int segmentos = await outbox.countPending(entityType: 'segmento');
    final int imagenes = await outbox.countPending(entityType: 'imagen');
    final int mensajes = await outbox.countPending(entityType: 'mensaje');
    final int videos = await outbox.countPending(entityType: 'video');
    return segmentos + imagenes + mensajes + videos;
  }

  Future<void> _persistLastDownload(MasterDataKind kind, DateTime when) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$lastDownloadPrefix${kind.name}',
      when.toIso8601String(),
    );
  }
}
