import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:leulit_flutter_actionmanager/leulit_flutter_actionmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/local/local_database.dart';
import '../../data/model/file_data.dart';
import '../../data/services/json_loader_service.dart';
import '../../domain/entities/ct_info_entity.dart';
import '../../domain/entities/pk_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../app_typed_actions.dart';
import 'connectivity_service.dart';

/// Group identifier que distingue los ficheros `*-pk.json` del resto de
/// descargas que pasan por [JsonLoaderService].
const String kFileGroupPk = 'pk';

/// Servicio singleton que mantiene en memoria los puntos kilométricos de los
/// CTs del usuario. Mismo flujo que [GasoductosService] pero produciendo
/// `PkEntity` (puntos para una capa de marcadores).
class PksService extends GetxService {
  /// PKs disponibles en sesión (después de cargar online o desde caché).
  final pks = <PkEntity>[].obs;
  final isLoading = false.obs;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  String? _onLoadedHandlerId;
  String? _onCompletedHandlerId;

  Completer<void>? _runCompleter;
  final _entitiesBuffer = <PkEntity>[];

  JsonLoaderService get _loader => Get.find<JsonLoaderService>();
  ConnectivityService get _conn => Get.find<ConnectivityService>();

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

  /// Carga los PKs solo si no se han cargado aún en esta sesión.
  Future<void> ensureLoaded() async {
    if (_loaded || isLoading.value) return;
    await _runOnce(forceRefresh: false);
  }

  /// Fuerza recarga ignorando la caché de sesión (pero usando caché SQLite si
  /// no hay conexión).
  Future<void> reload() async {
    _loaded = false;
    await _runOnce(forceRefresh: true);
  }

  Future<void> _runOnce({required bool forceRefresh}) async {
    isLoading.value = true;
    try {
      final ctInfos = await _ctInfosFromPrefs();

      if (!_conn.isConnected) {
        await _loadFromCache(ctInfos.map((c) => c.id).toList());
        _loaded = true;
        return;
      }

      if (!forceRefresh) {
        final ctIds = ctInfos.map((c) => c.id).toList();
        if (await _hasCache(ctIds)) {
          await _loadFromCache(ctIds);
          _loaded = true;
          return;
        }
      }

      _entitiesBuffer.clear();
      _runCompleter = Completer<void>();

      final files = ctInfos
          .map((c) => FileData(
                group: kFileGroupPk,
                filename: c.pkUrl,
                tag: c.id,
              ))
          .toList();

      await _loader.loadFiles(files);
      await _runCompleter?.future
          .timeout(const Duration(seconds: 1), onTimeout: () {});

      pks.assignAll(_entitiesBuffer);
      if (_entitiesBuffer.isNotEmpty) {
        await _cachePks(_entitiesBuffer);
      }
      _loaded = true;
    } catch (e) {
      debugPrint('PksService: error cargando PKs — $e');
    } finally {
      _entitiesBuffer.clear();
      _runCompleter = null;
      isLoading.value = false;
    }
  }

  // ──────────────────────────── Listeners ────────────────────────────

  void _onGeoJsonLoaded(ActionEvent<FileLoadGeoJsonResult> event) {
    final result = event.data;
    if (result is! FileLoadGeoJsonResult) return;
    if (result.originalFileData.group != kFileGroupPk) return;
    if (result.processedData.isEmpty) return;

    final ctId = result.originalFileData.tag is int
        ? result.originalFileData.tag as int
        : 0;
    try {
      final entities = PkEntity.fromGeoJson(result.processedData, ctId);
      _entitiesBuffer.addAll(entities);
    } catch (e) {
      debugPrint('PksService: parse error CT $ctId — $e');
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
        'SELECT COUNT(*) FROM pks WHERE ct_id IN ($placeholders)',
        ctIds,
      ),
    );
    return (count ?? 0) > 0;
  }

  Future<void> _loadFromCache(List<int> ctIds) async {
    if (ctIds.isEmpty) {
      pks.clear();
      return;
    }
    final db = await LocalDatabase.instance.database;
    final placeholders = ctIds.map((_) => '?').join(',');
    final rows = await db.query(
      'pks',
      where: 'ct_id IN ($placeholders)',
      whereArgs: ctIds,
    );
    pks.assignAll(rows.map(_rowToPk).toList());
  }

  Future<void> _cachePks(List<PkEntity> entities) async {
    if (entities.isEmpty) return;
    final db = await LocalDatabase.instance.database;
    final batch = db.batch();
    for (final p in entities) {
      batch.insert(
        'pks',
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

  PkEntity _rowToPk(Map<String, Object?> row) => PkEntity(
        id: row['id'] as String,
        ctId: row['ct_id'] as int,
        label: (row['label'] as String?) ?? '',
        point: LatLng(
          (row['lat'] as num).toDouble(),
          (row['lng'] as num).toDouble(),
        ),
      );
}
