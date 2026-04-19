import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/sync/contracts/local_store.dart';
import '../../domain/entities/imagen_segmento_entity.dart';

/// SQLite-backed [LocalStore] for [ImagenSegmentoEntity].
///
/// Writes against the pre-existing `imagenes_actividad` table defined in
/// `LocalDatabase`. The entity's `clientId` equals `localId` (the table's
/// primary key) per the `Syncable` mapping on [ImagenSegmentoEntity].
class ImagenLocalStore implements LocalStore<ImagenSegmentoEntity> {
  static const String _table = 'imagenes_actividad';

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
      where: 'local_id = ?',
      whereArgs: [clientId],
    );
  }

  @override
  Future<ImagenSegmentoEntity?> findByClientId(String clientId) async {
    final rows = await _db.query(
      _table,
      where: 'local_id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ImagenSegmentoEntity.fromMap(rows.first);
  }

  @override
  Future<List<ImagenSegmentoEntity>> findAll() async {
    final rows = await _db.query(
      _table,
      orderBy: 'captured_at DESC',
    );
    return rows
        .map(ImagenSegmentoEntity.fromMap)
        .toList(growable: false);
  }

  @override
  Future<void> markSynced({
    required String clientId,
    String? remoteId,
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? _db;
    final values = <String, Object?>{
      'sync_status': SyncStatus.uploaded.name,
    };
    if (remoteId != null) {
      final parsed = int.tryParse(remoteId);
      if (parsed != null) {
        values['remote_id'] = parsed;
      } else {
        debugPrint(
          '[ImagenLocalStore] markSynced: remoteId "$remoteId" is not a '
          'valid int; leaving remote_id column untouched for clientId=$clientId',
        );
      }
    }
    await executor.update(
      _table,
      values,
      where: 'local_id = ?',
      whereArgs: [clientId],
    );
  }
}
