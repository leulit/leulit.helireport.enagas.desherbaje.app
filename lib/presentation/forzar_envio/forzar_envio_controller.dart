import 'package:get/get.dart';
import 'package:helireport_desherbaje/core/my_getx_controller.dart';

import '../../core/app_log.dart';
import '../../core/result/data_result.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/sync/engine/sync_engine.dart';
import '../../data/repository/auth_repository_impl.dart';
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
  }) : _authRepo = authRepository ?? AuthRepositoryImpl();

  final GetSegmentosUseCase _useCase;
  final SyncEngine _engine;
  final ConnectivityService _connectivity;
  final AuthRepository _authRepo;

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

  /// Fuerza el envío a la nube de las entidades vinculadas a [segmento]:
  /// segmento → imagen → mensaje (en ese orden). Cada tipo se drena por
  /// separado; si el primer tipo provoca un authExpired, se corta el bucle
  /// y el [AuthExpirationHandler] gestiona el logout.
  Future<void> enviarCloud(SegmentoEntity segmento) async {
    if (!_connectivity.isConnected) {
      lastError.value = 'No hay conexión a internet.';
      AppLog.w('ForzarEnvioController.enviarCloud: sin red, abortando.');
      return;
    }

    // Usa el id remoto si existe; si no, la UI no puede distinguir qué segmento
    // está enviando, pero el drain drena por tipo (no por id), así que es correcto.
    final displayId = segmento.id ?? -1;
    if (enviandoIds.contains(displayId)) return; // guard re-entrancia
    enviandoIds.add(displayId);
    lastError.value = '';
    lastDrainSummary.value = null;

    try {
      var combined = const DrainSummary();

      for (final entityType in const ['segmento', 'imagen', 'video', 'mensaje']) {
        AppLog.i('ForzarEnvioController: drenando tipo "$entityType"...');
        final summary = await _engine.drain(entityType: entityType);
        combined = DrainSummary(
          succeeded: combined.succeeded + summary.succeeded,
          retryable: combined.retryable + summary.retryable,
          rejected: combined.rejected + summary.rejected,
          conflicts: combined.conflicts + summary.conflicts,
          authExpired: combined.authExpired || summary.authExpired,
        );
        if (summary.authExpired) {
          // AuthExpirationHandler ya gestiona logout; solo cortamos el bucle.
          AppLog.w('ForzarEnvioController: auth expirado en "$entityType", abortando drain.');
          break;
        }
      }

      lastDrainSummary.value = combined;
      if (combined.rejected > 0 || combined.conflicts > 0) {
        AppLog.w(
          'ForzarEnvioController.enviarCloud: '
          'rechazados=${combined.rejected} conflictos=${combined.conflicts}',
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

  /// Drena el outbox de todas las entidades con adapter registrado:
  /// segmento → imagen → mensaje → position. Si el primer tipo provoca
  /// authExpired, se corta el bucle.
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
      var combined = const DrainSummary();

      // Orden: segmento primero (FK origen), luego sus entidades dependientes.
      for (final entityType in const ['segmento', 'imagen', 'video', 'mensaje', 'position']) {
        AppLog.i('ForzarEnvioController: drenando tipo "$entityType"...');
        final summary = await _engine.drain(entityType: entityType);
        combined = DrainSummary(
          succeeded: combined.succeeded + summary.succeeded,
          retryable: combined.retryable + summary.retryable,
          rejected: combined.rejected + summary.rejected,
          conflicts: combined.conflicts + summary.conflicts,
          authExpired: combined.authExpired || summary.authExpired,
        );
        if (summary.authExpired) {
          AppLog.w('ForzarEnvioController: auth expirado en "$entityType", abortando drain.');
          break;
        }
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
