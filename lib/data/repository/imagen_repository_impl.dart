import '../../core/sync/contracts/sync_job.dart';
import '../../data/local/local_database.dart';
import '../../data/providers/image_upload_provider.dart';
import '../../domain/entities/imagen_segmento_entity.dart';

class ImagenRepositoryImpl {
  final _db = LocalDatabase.instance;
  final _uploadProvider = ImageUploadProvider();

  Future<void> saveLocal(ImagenSegmentoEntity imagen) async {
    final db = await _db.database;
    await db.insert('imagenes_actividad', imagen.toMap());
  }

  Future<List<ImagenSegmentoEntity>> getPendingByActividad(
      int actividadId) async {
    final db = await _db.database;
    final rows = await db.query(
      'imagenes_actividad',
      where: 'actividad_id = ? AND sync_status != ?',
      whereArgs: [actividadId, SyncStatus.uploaded.name],
    );
    return rows.map(ImagenSegmentoEntity.fromMap).toList();
  }

  Future<List<ImagenSegmentoEntity>> getAllByActividad(
      int actividadId) async {
    final db = await _db.database;
    final rows = await db.query(
      'imagenes_actividad',
      where: 'actividad_id = ?',
      whereArgs: [actividadId],
      orderBy: 'created_at DESC',
    );
    return rows.map(ImagenSegmentoEntity.fromMap).toList();
  }

  Future<void> updateStatus(String localId, SyncStatus status,
      {String? remoteUrl}) async {
    final db = await _db.database;
    await db.update(
      'imagenes_actividad',
      {
        'sync_status': status.name,
        if (remoteUrl != null) 'remote_url': remoteUrl,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> delete(String localId) async {
    final db = await _db.database;
    await db.delete(
      'imagenes_actividad',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> uploadPending(int actividadId) async {
    final pending = await getPendingByActividad(actividadId);
    for (final imagen in pending) {
      if (imagen.syncStatus == SyncStatus.uploaded) continue;
      await updateStatus(imagen.localId, SyncStatus.uploading);
      try {
        final remoteUrl = await _uploadProvider.uploadImage(imagen);
        await updateStatus(imagen.localId, SyncStatus.uploaded,
            remoteUrl: remoteUrl);
      } catch (_) {
        await updateStatus(imagen.localId, SyncStatus.error);
      }
    }
  }
}
