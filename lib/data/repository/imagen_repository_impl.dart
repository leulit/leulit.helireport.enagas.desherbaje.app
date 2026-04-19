import '../../data/local/local_database.dart';
import '../../data/providers/image_upload_provider.dart';
import '../../domain/entities/imagen_segmento_entity.dart';

/// Repositorio "ad-hoc" para `ImagenSegmentoEntity`. Convive con la capa de
/// sync genérica (`OfflineRepository<ImagenSegmentoEntity>` registrada en
/// `AppDI`) para los flujos directos del controller de captura.
class ImagenRepositoryImpl {
  final _db = LocalDatabase.instance;
  final _uploadProvider = ImageUploadProvider();

  static const String _table = 'imagenes_segmento';

  Future<void> saveLocal(ImagenSegmentoEntity imagen) async {
    final db = await _db.database;
    await db.insert(_table, imagen.toMap());
  }

  Future<List<ImagenSegmentoEntity>> getPendingBySegmento(int segmentoId) async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'segmento_id = ? AND needs_sync = 1',
      whereArgs: [segmentoId],
    );
    return rows.map(ImagenSegmentoEntity.fromMap).toList();
  }

  Future<List<ImagenSegmentoEntity>> getAllBySegmento(int segmentoId) async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'segmento_id = ?',
      whereArgs: [segmentoId],
      orderBy: 'capturada_at DESC',
    );
    return rows.map(ImagenSegmentoEntity.fromMap).toList();
  }

  Future<void> markUploaded(
    String clientId, {
    int? remoteId,
    String? url,
  }) async {
    final db = await _db.database;
    await db.update(
      _table,
      {
        'subida_at': DateTime.now().toIso8601String(),
        'synced_at': DateTime.now().toIso8601String(),
        'needs_sync': 0,
        if (remoteId != null) 'id': remoteId,
        if (url != null) 'url': url,
      },
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  Future<void> delete(String clientId) async {
    final db = await _db.database;
    await db.delete(_table, where: 'client_id = ?', whereArgs: [clientId]);
  }

  Future<void> uploadPending(int segmentoId) async {
    final pending = await getPendingBySegmento(segmentoId);
    for (final imagen in pending) {
      try {
        final remoteUrl = await _uploadProvider.uploadImage(imagen);
        await markUploaded(imagen.clientId, url: remoteUrl);
      } catch (_) {
        // Permanece en estado pendiente; el SyncEngine reintentará.
      }
    }
  }
}
