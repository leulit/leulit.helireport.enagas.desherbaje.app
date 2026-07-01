import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
import '../../domain/entities/gasoducto_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../presentation/mapa/lines_cut/polyline_hit_data.dart';
import '../app_log.dart';
import '../app_typed_actions.dart';
import '../sync/pull/cancel_token.dart';
import 'connectivity_service.dart';
import 'master_data_load_result.dart';

/// Group identifier usado por [JsonLoaderService] para distinguir los
/// ficheros de gasoductos del resto de descargas. Otros consumidores
/// (segmentos GIS, capas adicionales) usarán otros groups.
const String kFileGroupGasoducto = 'gasoducto';

/// Servicio singleton que mantiene en memoria las polylines de gasoductos
/// durante toda la sesión.
///
/// Flujo:
/// 1. `ensureLoaded()` o `reload()` calcula la lista de [FileData] (un fichero
///    `*-gasoductos.json` por cada CT del usuario logueado) y pide a
///    [JsonLoaderService] que los descargue.
/// 2. Mientras tanto, escucha `AppTypedActions.geoJsonLoaded` filtrando por
///    `group == kFileGroupGasoducto` y va construyendo `polylines` y la
///    caché SQLite incrementalmente.
/// 3. Si el dispositivo está offline, salta directamente a la caché local.
class GasoductosService extends GetxService {
  final polylines = <Polyline>[].obs;
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
  final _entitiesBuffer = <GasoductoEntity>[];

  /// Mapa ctId→nombre del CT (poblado desde `user.cts` en cada ejecución).
  /// Usado para construir el `hitValue` de cada polyline de forma que el
  /// motor de corte pueda resolver ctId/ctName sin acceder a prefs.
  Map<int, String> _ctNameById = const {};

  final ConnectivityService? _connArg;
  final JsonLoaderService? _loaderArg;

  // Resolución perezosa: no se llama a Get.find en construcción, así que
  // subclases/stubs de test que no usan estas deps no requieren registrarlas.
  JsonLoaderService get _loader => _loaderArg ?? AppDI.jsonLoaderService;
  ConnectivityService get _conn => _connArg ?? AppDI.connectivityService;

  GasoductosService({
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

  /// Carga las trazas solo si no se han cargado aún en esta sesión.
  /// Best-effort: errores se loguean y no propagan (path pasivo/prefetch).
  Future<void> ensureLoaded() async {
    if (_loaded || isLoading.value) return;
    try {
      await _runOnce(forceRefresh: false);
    } catch (e, st) {
      AppLog.w('GasoductosService.ensureLoaded: error silenciado', error: e, stackTrace: st);
    }
  }

  /// Fuerza recarga ignorando la caché de sesión (pero usando caché SQLite
  /// si no hay conexión). Propaga excepciones — el llamante (usuario) debe
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
      _ctNameById = {for (final c in ctInfos) c.id: c.nombre};

      // Sin conexión → caché local directamente.
      if (!_conn.isConnected) {
        await _loadFromCache(ctInfos.map((c) => c.id).toList());
        _loaded = true;
        resultSource = MasterDataSource.cache;
        fetchedCount = polylines.length;
        return MasterDataLoadResult(resultSource, fetchedCount);
      }

      // Si no es refresh forzado y la caché tiene datos, evitamos red.
      if (!forceRefresh) {
        final ctIds = ctInfos.map((c) => c.id).toList();
        if (await _hasCache(ctIds)) {
          await _loadFromCache(ctIds);
          _loaded = true;
          resultSource = MasterDataSource.cache;
          fetchedCount = polylines.length;
          return MasterDataLoadResult(resultSource, fetchedCount);
        }
      }

      _entitiesBuffer.clear();
      _runCompleter = Completer<void>();

      final files = ctInfos
          .map((c) => FileData(
                group: kFileGroupGasoducto,
                filename: c.gasoductosUrl,
                tag: c.id,
              ))
          .toList();

      totalFiles.value = files.length;
      processedFiles.value = 0;

      await _loader.loadFiles(files, token: token);
      // El pipeline ya ha terminado al volver de `loadFiles`, pero esperamos
      // al evento `geoJsonLoadCompleted` por si llega tras un microtask
      // (broadcast asíncrono). Timeout de 1s como salvaguarda.
      await _runCompleter?.future
          .timeout(const Duration(seconds: 1), onTimeout: () {});

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
        AppLog.w('GasoductosService: descarga parcial $succeeded/$attempted ficheros');
      }

      // Capture count BEFORE finally clears the buffer.
      fetchedCount = _entitiesBuffer.length;
      resultSource = MasterDataSource.network;

      polylines.assignAll(_toPolylines(_entitiesBuffer));
      if (_entitiesBuffer.isNotEmpty) {
        await _cacheGasoductos(_entitiesBuffer);
      }
      _loaded = true;
      return MasterDataLoadResult(resultSource, fetchedCount);
    } finally {
      _entitiesBuffer.clear();
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
    if (result.originalFileData.group != kFileGroupGasoducto) return;

    processedFiles.value = processedFiles.value + 1;

    if (result.processedData.isEmpty) return;

    final ctId =
        result.originalFileData.tag is int ? result.originalFileData.tag as int : 0;
    try {
      final entities =
          GasoductoEntity.fromGeoJson(result.processedData, ctId);
      _entitiesBuffer.addAll(entities);
    } catch (e) {
      debugPrint('GasoductosService: parse error CT $ctId — $e');
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
        'SELECT COUNT(*) FROM gasoductos WHERE ct_id IN ($placeholders)',
        ctIds,
      ),
    );
    return (count ?? 0) > 0;
  }

  Future<void> _loadFromCache(List<int> ctIds) async {
    if (ctIds.isEmpty) {
      polylines.clear();
      return;
    }
    final db = await LocalDatabase.instance.database;
    final placeholders = ctIds.map((_) => '?').join(',');
    final rows = await db.query(
      'gasoductos',
      where: 'ct_id IN ($placeholders)',
      whereArgs: ctIds,
    );
    polylines.assignAll(rows.map(_rowToPolyline).toList());
  }

  Future<void> _cacheGasoductos(List<GasoductoEntity> gasoductos) async {
    if (gasoductos.isEmpty) return;
    final db = await LocalDatabase.instance.database;
    final batch = db.batch();
    for (final g in gasoductos) {
      batch.insert(
        'gasoductos',
        {
          'id': g.id,
          'nombre': g.nombre,
          'ct_id': g.ctId,
          'points_json': jsonEncode(
            g.points
                .map((p) => {'lat': p.latitude, 'lng': p.longitude})
                .toList(),
          ),
          'color_value': g.colorValue,
          'stroke_width': g.strokeWidth,
          'synced_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // ──────────────────────────── Mappers ────────────────────────────

  List<Polyline> _toPolylines(List<GasoductoEntity> gasoductos) => gasoductos
      .map(
        (g) => Polyline(
          points: g.points,
          color: Color(g.colorValue),
          strokeWidth: g.strokeWidth,
          hitValue: GasoductoHitData(
            id: g.id,
            ctId: g.ctId,
            ct: _ctNameById[g.ctId] ?? '',
            name: g.nombre,
          ),
        ),
      )
      .toList();

  Polyline _rowToPolyline(Map<String, Object?> row) {
    final pointsRaw = jsonDecode(row['points_json'] as String) as List<dynamic>;
    final points = pointsRaw.map((p) {
      final m = p as Map<String, dynamic>;
      return LatLng(
        (m['lat'] as num).toDouble(),
        (m['lng'] as num).toDouble(),
      );
    }).toList();
    final ctId = row['ct_id'] as int? ?? 0;
    final nombre = (row['nombre'] as String?) ?? '';
    return Polyline(
      points: points,
      color: Color(row['color_value'] as int),
      strokeWidth: (row['stroke_width'] as num).toDouble(),
      hitValue: GasoductoHitData(
        id: (row['id'] as String?) ?? '$ctId',
        ctId: ctId,
        ct: _ctNameById[ctId] ?? '',
        name: nombre,
      ),
    );
  }
}
