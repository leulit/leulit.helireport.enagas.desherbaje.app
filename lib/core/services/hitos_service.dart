import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:helireport_desherbaje/core/app_di.dart';
import 'package:latlong2/latlong.dart';
import 'package:leulit_flutter_actionmanager/leulit_flutter_actionmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/local/local_database.dart';
import '../../data/model/file_data.dart';
import '../../data/services/json_loader_service.dart';
import '../../domain/entities/ct_info_entity.dart';
import '../../domain/entities/hito_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../app_log.dart';
import '../app_typed_actions.dart';
import '../sync/pull/cancel_token.dart';
import 'connectivity_service.dart';
import 'master_data_load_result.dart';

/// Group identifier que distingue los ficheros `*-hitos.json` del resto de
/// descargas que pasan por [JsonLoaderService].
const String kFileGroupHitos = 'hitos';

/// Servicio singleton que mantiene en memoria los hitos de los
/// CTs del usuario. Mismo flujo que [GasoductosService] pero produciendo
/// `HitoEntity` (puntos para una capa de marcadores).
class HitosService extends GetxService {
  /// Hitos disponibles en sesión (después de cargar online o desde caché).
  final ValueNotifier<List<HitoEntity>> hitos =
      ValueNotifier<List<HitoEntity>>(const []);
  final isLoading = false.obs;
  /// Total de ficheros del lote en curso (0 cuando no hay carga activa).
  final totalFiles = 0.obs;
  /// Ficheros ya procesados dentro del lote en curso.
  final processedFiles = 0.obs;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  String? _onLoadedHandlerId;
  String? _onCompletedHandlerId;

  Completer<void>? _runCompleter;
  final _entitiesBuffer = <HitoEntity>[];
  // Parseos en curso (compute() por fichero). `_runOnce` debe esperarlos
  // TODOS antes de dar la descarga por completa: el parseo ahora corre en
  // otro isolate, así que ya no termina síncronamente dentro del handler
  // de `geoJsonLoaded` como antes.
  final _pendingParses = <Future<void>>[];

  final ConnectivityService? _connArg;
  final JsonLoaderService? _loaderArg;

  // Resolución perezosa: no se llama a Get.find en construcción, así que
  // subclases/stubs de test que no usan estas deps no requieren registrarlas.
  JsonLoaderService get _loader => _loaderArg ?? AppDI.jsonLoaderService;
  ConnectivityService get _conn => _connArg ?? AppDI.connectivityService;

  HitosService({
    ConnectivityService? conn,
    JsonLoaderService? loader,
  })  : _connArg = conn,
        _loaderArg = loader;

  @override
  void onInit() {
    super.onInit();
    _onLoadedHandlerId = AppTypedActions.geoJsonLoaded.on(_onGeoJsonLoaded);
    _onCompletedHandlerId =
        AppTypedActions.geoJsonLoadCompleted.on(_onGeoJsonCompleted);
  }

  @override
  void onClose() {
    if (_onLoadedHandlerId != null) {
      AppTypedActions.geoJsonLoaded.off(_onLoadedHandlerId!);
    }
    if (_onCompletedHandlerId != null) {
      AppTypedActions.geoJsonLoadCompleted.off(_onCompletedHandlerId!);
    }
    super.onClose();
  }

  /// Carga los hitos solo si no se han cargado aún en esta sesión.
  /// Best-effort: errores se loguean y no propagan (path pasivo/prefetch).
  Future<void> ensureLoaded() async {
    if (_loaded || isLoading.value) return;
    try {
      await _runOnce(forceRefresh: false);
    } catch (e, st) {
      AppLog.w('HitosService.ensureLoaded: error silenciado', error: e, stackTrace: st);
    }
  }

  /// Fuerza recarga ignorando la caché de sesión (pero usando caché SQLite si
  /// no hay conexión). Propaga excepciones — el llamante (usuario) debe
  /// manejarlas mostrando error en UI.
  Future<MasterDataLoadResult> reload({CancelToken? token}) async {
    _loaded = false;
    return _runOnce(forceRefresh: true, token: token);
  }

  Future<MasterDataLoadResult> _runOnce({
    required bool forceRefresh,
    CancelToken? token,
  }) async {
    isLoading.value = true;
    int fetchedCount = 0;
    MasterDataSource resultSource = MasterDataSource.empty;
    try {
      final ctInfos = await _ctInfosFromPrefs();

      if (!_conn.isConnected) {
        await _loadFromCache(ctInfos.map((c) => c.id).toList());
        _loaded = true;
        resultSource = MasterDataSource.cache;
        fetchedCount = hitos.value.length;
        return MasterDataLoadResult(resultSource, fetchedCount);
      }

      if (!forceRefresh) {
        final ctIds = ctInfos.map((c) => c.id).toList();
        if (await _hasCache(ctIds)) {
          await _loadFromCache(ctIds);
          _loaded = true;
          resultSource = MasterDataSource.cache;
          fetchedCount = hitos.value.length;
          return MasterDataLoadResult(resultSource, fetchedCount);
        }
      }

      _entitiesBuffer.clear();
      _pendingParses.clear();
      _runCompleter = Completer<void>();

      final files = ctInfos
          .map((c) => FileData(
                group: kFileGroupHitos,
                filename: c.hitosUrl,
                tag: c.id,
              ))
          .toList();

      totalFiles.value = files.length;
      processedFiles.value = 0;

      await _loader.loadFiles(files, token: token);
      await _runCompleter?.future
          .timeout(const Duration(seconds: 1), onTimeout: () {});
      // Los ficheros ya llegaron (evento `geoJsonLoaded`/`Completed`), pero
      // su parseo corre en isolates aparte (compute()) y puede seguir en
      // vuelo. Esperamos a que todos terminen antes de dar la carga por
      // completa.
      if (_pendingParses.isNotEmpty) {
        await Future.wait(_pendingParses);
      }

      // NF-13: re-check cancellation before persisting.
      if (token?.isCancelled ?? false) {
        resultSource = MasterDataSource.cache;
        fetchedCount = 0;
        return MasterDataLoadResult(resultSource, fetchedCount);
      }

      // No silent failure: if the network run downloaded 0 files successfully
      // (every file errored), surface it instead of reporting a green success.
      // A legit empty file (200, no features) still fires a success event, so
      // processedFiles > 0 and does not trip this.
      final int attempted = totalFiles.value;
      final int succeeded = processedFiles.value;
      if (attempted > 0 && succeeded == 0) {
        throw StateError(
          'Descarga fallida: 0/$attempted ficheros. Revisa la conexión o el backend.',
        );
      }
      if (succeeded < attempted) {
        AppLog.w('HitosService: descarga parcial $succeeded/$attempted ficheros');
      }

      // Capture count BEFORE finally clears the buffer.
      fetchedCount = _entitiesBuffer.length;
      resultSource = MasterDataSource.network;

      hitos.value = List<HitoEntity>.unmodifiable(_entitiesBuffer);
      if (_entitiesBuffer.isNotEmpty) {
        await _cacheHitos(_entitiesBuffer);
      }
      _loaded = true;
      return MasterDataLoadResult(resultSource, fetchedCount);
    } finally {
      _entitiesBuffer.clear();
      _pendingParses.clear();
      _runCompleter = null;
      isLoading.value = false;
      totalFiles.value = 0;
      processedFiles.value = 0;
    }
  }

  // ──────────────────────────── Listeners ────────────────────────────

  void _onGeoJsonLoaded(ActionEvent<FileLoadGeoJsonResult> event) {
    final result = event.data;
    if (result is! FileLoadGeoJsonResult) return;
    if (result.originalFileData.group != kFileGroupHitos) return;

    processedFiles.value = processedFiles.value + 1;

    if (result.rawJson.isEmpty) return;

    final ctId = result.originalFileData.tag is int
        ? result.originalFileData.tag as int
        : 0;
    // Parseo pesado (~48k hitos, incluye el jsonDecode) fuera del hilo de
    // UI. `_runOnce` espera este future vía `_pendingParses` antes de
    // considerar la carga completa.
    _pendingParses.add(_parseAndBuffer(result.rawJson, ctId));
  }

  Future<void> _parseAndBuffer(String raw, int ctId) async {
    try {
      final flat = await compute(parseHitosFlat, (raw: raw, ctId: ctId));
      _entitiesBuffer.addAll(flat.map(hitoFromFlat));
    } catch (e) {
      debugPrint('HitosService: parse error CT $ctId — $e');
    }
  }

  void _onGeoJsonCompleted(ActionEvent<void> _) {
    if (_runCompleter != null && !_runCompleter!.isCompleted) {
      _runCompleter!.complete();
    }
  }

  // ──────────────────────────── Caché SQLite ────────────────────────────

  Future<List<CtInfo>> _ctInfosFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user_json');
    if (userJson == null) return const <CtInfo>[];
    try {
      final user =
          UserModel.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      return user.cts
          .map((c) => CtInfo(id: c.ctid, nombre: c.ct, filename: c.ct))
          .toList();
    } catch (_) {
      return const <CtInfo>[];
    }
  }

  Future<bool> _hasCache(List<int> ctIds) async {
    if (ctIds.isEmpty) return false;
    final db = await LocalDatabase.instance.database;
    final placeholders = ctIds.map((_) => '?').join(',');
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM hitos WHERE ct_id IN ($placeholders)',
        ctIds,
      ),
    );
    return (count ?? 0) > 0;
  }

  Future<void> _loadFromCache(List<int> ctIds) async {
    if (ctIds.isEmpty) {
      hitos.value = const [];
      return;
    }
    final db = await LocalDatabase.instance.database;
    final placeholders = ctIds.map((_) => '?').join(',');
    final rows = await db.query(
      'hitos',
      where: 'ct_id IN ($placeholders)',
      whereArgs: ctIds,
    );
    hitos.value =
        List<HitoEntity>.unmodifiable(rows.map(_rowToHito));
  }

  Future<void> _cacheHitos(List<HitoEntity> entities) async {
    if (entities.isEmpty) return;
    final db = await LocalDatabase.instance.database;
    final batch = db.batch();
    for (final p in entities) {
      batch.insert(
        'hitos',
        {
          'id': p.id,
          'ct_id': p.ctId,
          'label': p.label,
          'lat': p.point.latitude,
          'lng': p.point.longitude,
          'synced_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  HitoEntity _rowToHito(Map<String, Object?> row) => HitoEntity(
        id: row['id'] as String,
        ctId: row['ct_id'] as int,
        label: (row['label'] as String?) ?? '',
        point: LatLng(
          (row['lat'] as num).toDouble(),
          (row['lng'] as num).toDouble(),
        ),
      );
}
