import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_router.dart';
import '../../core/my_getx_controller.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/gasoductos_service.dart';
import '../../core/services/pks_service.dart';
import '../../core/sync/sync.dart';
import '../../data/repository/auth_repository_impl.dart';
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
    ConnectivityService? connectivity,
  })  : _auth = authRepository ?? AuthRepositoryImpl(),
        _gasoductos = gasoductosService ?? Get.find<GasoductosService>(),
        _pks = pksService ?? Get.find<PksService>(),
        _connectivity = connectivity ?? Get.find<ConnectivityService>();

  static const String _lastDownloadPrefix = 'sync_master_last_download_';

  final AuthRepository _auth;
  final GasoductosService _gasoductos;
  final PksService _pks;
  final ConnectivityService _connectivity;

  // ─────────────────────────────── State ───────────────────────────────

  final isOnline = true.obs;
  final isWorking = false.obs;
  final lastError = Rxn<String>();

  /// Fila por cada [MasterDataKind] — orden estable.
  final rows = <MasterDataRow>[].obs;

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
  }

  Future<void> _initRows() async {
    final prefs = await SharedPreferences.getInstance();
    rows.assignAll(MasterDataKind.values.map((k) {
      final last = prefs.getString('$_lastDownloadPrefix${k.name}');
      return MasterDataRow(
        kind: k,
        status: k == MasterDataKind.posicionesFijas
            ? MasterDataStatus.unavailable
            : MasterDataStatus.idle,
        lastDownloadAt: last == null ? null : DateTime.tryParse(last),
      );
    }));
  }

  // ─────────────────────────────── Actions ─────────────────────────────

  /// Descarga todas las filas disponibles (omite las marcadas como
  /// `unavailable`). Cooperativamente cancelable.
  Future<void> descargarTodo() async {
    if (isWorking.value) return;
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
    Get.offAllNamed(AppRoutes.login);
  }

  // ─────────────────────────── Internals ───────────────────────────────

  MasterDataRow _rowFor(MasterDataKind kind) =>
      rows.firstWhere((r) => r.kind == kind);

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
      ),
    );

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
          await _gasoductos.reload();
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
          await _pks.reload();
        case MasterDataKind.segmentos:
          final int pending = await _countPendingForSegmentos();
          if (pending > 0) {
            _updateRow(
              kind,
              _rowFor(kind).copyWith(
                status: MasterDataStatus.error,
                errorMessage:
                    'Hay $pending cambios pendientes de subir. Súbelos antes de descargar la lista actualizada.',
                clearProgress: true,
                clearProgressLabel: true,
              ),
            );
            return;
          }
          final PullSummary? summary =
              await OfflineModule.runPull('segmento', token: sharedToken);
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
        case MasterDataKind.posicionesFijas:
          // No disponible aún — protegido más arriba; nunca debería llegar.
          return;
      }
      final now = DateTime.now();
      await _persistLastDownload(kind, now);
      _updateRow(
        kind,
        _rowFor(kind).copyWith(
          status: MasterDataStatus.success,
          lastDownloadAt: now,
          clearError: true,
          clearProgress: true,
          clearProgressLabel: true,
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
      final label = t > 0 ? '$p / $t' : null;
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
    final OutboxQueue outbox = Get.find<OutboxQueue>();
    final int segmentos = await outbox.countPending(entityType: 'segmento');
    final int imagenes = await outbox.countPending(entityType: 'imagen');
    final int mensajes = await outbox.countPending(entityType: 'mensaje');
    return segmentos + imagenes + mensajes;
  }

  Future<void> _persistLastDownload(MasterDataKind kind, DateTime when) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_lastDownloadPrefix${kind.name}',
      when.toIso8601String(),
    );
  }
}
