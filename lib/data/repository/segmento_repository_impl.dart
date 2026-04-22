import 'package:sqflite/sqflite.dart';

import '../../core/result/data_result.dart';
import '../../data/local/local_database.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/repository/segmento_repository.dart';
import '../providers/segmento_data_provider_factory.dart';
import '../sync/segmento_local_store.dart';

class SegmentoRepositoryImpl implements SegmentoRepository {
  final _db = LocalDatabase.instance;

  @override
  Future<DataResult<List<SegmentoEntity>>> getByOperador(
    int operadorId,
    List<int> cts,
  ) async {
    final provider = SegmentoDataProviderFactory.create();
    final result = await provider.getByOperador(operadorId, cts);
    if (result.isSuccess) {
      final remote = result.dataOrNull ?? const <SegmentoEntity>[];
      // Conserva ediciones locales aún no propagadas al backend: no refresca
      // la caché de filas con `needs_sync = 1` y devuelve su versión local
      // en lugar de la remota, para que el usuario siga viendo lo que acaba
      // de guardar.
      final pending = await _readPendingSyncById();
      final safeToCache = remote
          .where((s) => s.id == null || !pending.containsKey(s.id))
          .toList(growable: false);
      await _cacheSegmentos(safeToCache);
      final merged = remote
          .map((s) => (s.id != null && pending[s.id] != null) ? pending[s.id]! : s)
          .toList(growable: false);
      final locales = await _readLocalOnly();
      if (locales.isEmpty) return DataResult.success(merged);
      return DataResult.success([...locales, ...merged]);
    }
    return result;
  }

  Future<Map<int, SegmentoEntity>> _readPendingSyncById() async {
    final db = await _db.database;
    final rows = await db.query(
      'segmentos',
      where: 'needs_sync = 1 AND id >= 0',
    );
    final map = <int, SegmentoEntity>{};
    for (final row in rows) {
      final entity = SegmentoLocalStore.rowToEntity(row);
      final id = entity.id;
      if (id != null) map[id] = entity;
    }
    return map;
  }

  /// Upsert completo de un segmento en SQLite. Marca la fila como pendiente
  /// de sync (`needs_sync = 1`) para que la capa de sincronización la empuje
  /// al backend cuando haya conectividad.
  ///
  /// Pensado para persistir ediciones locales (estado / tipo / descripción)
  /// antes —o en paralelo— del push remoto.
  Future<void> saveLocal(SegmentoEntity entity) async {
    final db = await _db.database;
    final row = SegmentoLocalStore.entityToRow(entity);
    await db.insert(
      'segmentos',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Persiste un segmento creado localmente (aún no enviado al backend) en
  /// SQLite. Asigna el siguiente id negativo (-1, -2, -3…) para evitar
  /// colisión con los ids remotos positivos, y lo marca `needs_sync = 1`.
  /// Devuelve la entidad con el id asignado.
  Future<SegmentoEntity> insertLocalOnly(SegmentoEntity entity) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT MIN(id) AS min_id FROM segmentos',
    );
    final currentMin = rows.first['min_id'] as int?;
    // Si el mínimo existente es positivo (o no hay filas), arrancamos en -1.
    entity.id = (currentMin == null || currentMin >= 0) ? -1 : currentMin - 1;
    final row = SegmentoLocalStore.entityToRow(entity)..['needs_sync'] = 1;
    await db.insert(
      'segmentos',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return entity;
  }

  Future<List<SegmentoEntity>> _readLocalOnly() async {
    final db = await _db.database;
    final rows = await db.query(
      'segmentos',
      where: 'id < 0',
      orderBy: 'id ASC', // más recientes (más negativos) primero
    );
    return rows
        .map(SegmentoLocalStore.rowToEntity)
        .toList(growable: false);
  }

  @override
  Future<DataResult<SegmentoEntity?>> getById(int id) {
    final provider = SegmentoDataProviderFactory.create();
    return provider.getById(id);
  }

  @override
  Future<DataResult<bool>> updateEstado(int id, EstadoActividad estado) {
    final provider = SegmentoDataProviderFactory.create();
    return provider.updateEstado(id, estado);
  }

  Future<void> _cacheSegmentos(List<SegmentoEntity> segmentos) async {
    if (segmentos.isEmpty) return;
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final s in segmentos) {
      final row = SegmentoLocalStore.entityToRow(s)
        ..['synced_at'] = now
        ..['needs_sync'] = 0;
      batch.insert(
        'segmentos',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
