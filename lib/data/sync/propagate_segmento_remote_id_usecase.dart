import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/app_di.dart';
import 'imagen_local_store.dart';
import 'mensaje_local_store.dart';
import 'video_local_store.dart';

/// Propaga el id de backend de un segmento recién sincronizado a sus
/// entidades hijas (imágenes, vídeos, mensajes) todavía locales.
///
/// Un segmento creado en la app no tiene `id` remoto hasta que se sube; sus
/// hijos se enlazan localmente por `segmento_client_id` (ver lección
/// "FKs de entidades hijas locales van por clientId" en CLAUDE.md). Los
/// adapters de imagen/video/mensaje, en cambio, envían al backend el `id`
/// numérico leído de `entity.segmentoId` — así que, en cuanto el segmento
/// obtiene su id remoto, hay que estampar ese id en la columna `segmento_id`
/// de todas sus filas hijas ANTES de drenarlas, o subirían sin vínculo.
///
/// Escritura en una única transacción: o se propaga a las tres tablas o a
/// ninguna.
class PropagateSegmentoRemoteIdUseCase {
  final Database _db;
  final ImagenLocalStore _imagenStore;
  final VideoLocalStore _videoStore;
  final MensajeLocalStore _mensajeStore;

  PropagateSegmentoRemoteIdUseCase({
    Database? db,
    ImagenLocalStore? imagenStore,
    VideoLocalStore? videoStore,
    MensajeLocalStore? mensajeStore,
  })  : _db = db ?? AppDI.database,
        _imagenStore = imagenStore ?? DI.get<ImagenLocalStore>(),
        _videoStore = videoStore ?? DI.get<VideoLocalStore>(),
        _mensajeStore = mensajeStore ?? DI.get<MensajeLocalStore>();

  /// Estampa [backendId] en la columna `segmento_id` de todas las imágenes,
  /// vídeos y mensajes cuyo `segmento_client_id` sea [segmentoClientId].
  Future<void> propagate(String segmentoClientId, int backendId) async {
    await _db.transaction((txn) async {
      await _imagenStore.setSegmentoRemoteId(
        segmentoClientId,
        backendId,
        txn: txn,
      );
      await _videoStore.setSegmentoRemoteId(
        segmentoClientId,
        backendId,
        txn: txn,
      );
      await _mensajeStore.setSegmentoRemoteId(
        segmentoClientId,
        backendId,
        txn: txn,
      );
    });
  }
}
