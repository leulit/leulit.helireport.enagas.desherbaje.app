import 'package:sqflite/sqflite.dart';

import '../../core/sync/contracts/local_store.dart';
import '../../domain/entities/imagen_segmento_entity.dart';

/// SQLite-backed [LocalStore] for [ImagenSegmentoEntity].
///
/// Persists in `imagenes_segmento` (schema v6). The entity's `clientId` is a
/// UUID generated at construction time and stored in the `client_id` column,
/// so the outbox is idempotent before the backend assigns a remote `id`.
class ImagenLocalStore implements LocalStore<ImagenSegmentoEntity> {
  static const String _table = 'imagenes_segmento';

  final Database _db;

  ImagenLocalStore(this._db);

  @override
  Future<void> upsert(
    ImagenSegmentoEntity entity, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? _db;
    await executor.insert(
      _table,
      entity.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String clientId, {DatabaseExecutor? txn}) async {
    final executor = txn ?? _db;
    await executor.delete(
      _table,
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  @override
  Future<ImagenSegmentoEntity?> findByClientId(String clientId) async {
    final rows = await _db.query(
      _table,
      where: 'client_id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ImagenSegmentoEntity.fromMap(rows.first);
  }

  @override
  Future<List<ImagenSegmentoEntity>> findAll() async {
    final rows = await _db.query(_table, orderBy: 'capturada_at DESC');
    return rows.map(ImagenSegmentoEntity.fromMap).toList(growable: false);
  }

  @override
  Future<void> markSynced({
    required String clientId,
    String? remoteId,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? _db;
    final values = <String, Object?>{
      'synced_at': DateTime.now().toIso8601String(),
      'needs_sync': 0,
    };
    if (remoteId != null) {
      final parsed = int.tryParse(remoteId);
      if (parsed != null) values['id'] = parsed;
    }
    await executor.update(
      _table,
      values,
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }
}
