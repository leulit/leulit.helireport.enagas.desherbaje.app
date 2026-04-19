import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/services/connectivity_service.dart';
import '../../data/local/local_database.dart';
import '../../data/providers/gasoductos_data_provider.dart';
import '../../domain/entities/ct_info_entity.dart';
import '../../domain/entities/gasoducto_entity.dart';

class GasoductosRepository {
  final _provider = GasoductosDataProvider();
  final _db = LocalDatabase.instance;

  Future<List<Polyline>> getPolylinesForCts(
    List<CtInfo> ctInfos, {
    bool forceRefresh = false,
  }) async {
    final ctIds = ctInfos.map((c) => c.id).toList();
    if (!forceRefresh && await hasCachedData(ctIds)) {
      return _loadFromCache(ctIds);
    }
    final isOnline = Get.find<ConnectivityService>().isConnected;
    if (isOnline) {
      final gasoductos = await _provider.loadForCts(ctInfos);
      if (gasoductos.isNotEmpty) {
        await _cacheGasoductos(gasoductos);
      }
      return _toPolylines(gasoductos);
    } else {
      return _loadFromCache(ctIds);
    }
  }

  List<Polyline> _toPolylines(List<GasoductoEntity> gasoductos) {
    return gasoductos
        .map(
          (g) => Polyline(
            points: g.points,
            color: Color(g.colorValue),
            strokeWidth: g.strokeWidth,
          ),
        )
        .toList();
  }

  Future<void> _cacheGasoductos(List<GasoductoEntity> gasoductos) async {
    if (gasoductos.isEmpty) return;
    final db = await _db.database;
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

  Future<List<Polyline>> _loadFromCache(List<int> ctIds) async {
    if (ctIds.isEmpty) return [];
    final db = await _db.database;
    final placeholders = ctIds.map((_) => '?').join(',');
    final rows = await db.query(
      'gasoductos',
      where: 'ct_id IN ($placeholders)',
      whereArgs: ctIds,
    );
    return rows.map((row) {
      final pointsRaw =
          jsonDecode(row['points_json'] as String) as List<dynamic>;
      final points = pointsRaw.map((p) {
        final m = p as Map<String, dynamic>;
        return LatLng(
          (m['lat'] as num).toDouble(),
          (m['lng'] as num).toDouble(),
        );
      }).toList();
      return Polyline(
        points: points,
        color: Color(row['color_value'] as int),
        strokeWidth: (row['stroke_width'] as num).toDouble(),
      );
    }).toList();
  }

  Future<bool> hasCachedData(List<int> ctIds) async {
    if (ctIds.isEmpty) return false;
    final db = await _db.database;
    final placeholders = ctIds.map((_) => '?').join(',');
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM gasoductos WHERE ct_id IN ($placeholders)',
        ctIds,
      ),
    );
    return (count ?? 0) > 0;
  }
}
