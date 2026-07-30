import 'dart:io';

import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/api_endpoints.dart';
import '../../core/app_di.dart';
import '../../core/app_log.dart';
import '../../core/sync/contracts/sync_job.dart';
import '../../core/sync/outbox/outbox_queue.dart';
import '../../domain/entities/imagen_segmento_entity.dart';
import '../../domain/entities/segmento_entity.dart';
import '../../domain/entities/video_segmento_entity.dart';
import '../model/mensaje_entity.dart';
import '../network/network_error.dart';
import '../network/network_service.dart';
import 'adapter_support.dart';
import 'imagen_local_store.dart';
import 'mensaje_local_store.dart';
import 'segmento_local_store.dart';
import 'video_local_store.dart';

/// Deletes a local file best-effort. Injectable so tests never touch the disk.
typedef LocalFileDeleter = Future<void> Function(String path);

Future<void> _defaultDeleteFile(String path) async {
  if (path.isEmpty) return;
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (e, st) {
    // Best-effort: the content is already on the backend (that is why the row
    // was synced). A leftover cache file is not lost data — log and move on.
    AppLog.w(
      'PurgeSyncedSegmentoUseCase: could not delete local file "$path".',
      error: e,
      stackTrace: st,
    );
  }
}

/// Result of evaluating a single segment for purge.
enum PurgeStatus {
  /// Segment and every dependent were fully synced → row + file + synced
  /// outbox jobs deleted.
  purged,

  /// Todo subido y `sync-complete` confirmado, pero el segmento se queda en
  /// local porque su estado no es terminal (`ejecución`, `propuesta`…): el
  /// operario sigue trabajándolo y `GET /segmentos/contratista` no lo sirve,
  /// así que borrarlo sería perderlo.
  finalizedKept,

  /// At least one part (segment or a dependent) still had a
  /// pending/syncing/rejected outbox job → nothing was deleted.
  keptUnsynced,

  /// Segment has no remote id (never accepted by the backend) → by definition
  /// not synced; skipped without touching anything.
  skippedNoRemoteId,

  /// Everything was synced, but the `sync-complete` finalize call to the
  /// backend failed → nothing was deleted; retried on the next send.
  finalizeFailed,
}

/// Outcome of [PurgeSyncedSegmentoUseCase.purgeIfFullySynced].
class PurgeOutcome {
  final PurgeStatus status;
  final int imagenes;
  final int videos;
  final int mensajes;
  final List<String> filesDeleted;

  const PurgeOutcome({
    required this.status,
    this.imagenes = 0,
    this.videos = 0,
    this.mensajes = 0,
    this.filesDeleted = const [],
  });
}

/// The set of `clientId`s that are NOT yet on the backend, per entity type.
/// A `clientId` is "unsynced" when it still has a `pending`, `syncing`, or
/// `rejected` outbox job (delete ops excluded — a delete does not represent
/// un-uploaded field data). Mirrors `DetectConflictsTask._pendingClientIds`.
class UnsyncedSets {
  final Set<String> segmento;
  final Set<String> imagen;
  final Set<String> video;
  final Set<String> mensaje;

  const UnsyncedSets({
    required this.segmento,
    required this.imagen,
    required this.video,
    required this.mensaje,
  });
}

/// Deletes a finalized segment and ALL its dependent imágenes/vídeos/mensajes
/// (local row + local file + synced outbox job) ONLY when the segment and every
/// dependent is fully synced. If ANY part still carries a pending/syncing/
/// rejected outbox job, nothing is deleted — the whole segment is kept for
/// retry. The cascade delete is atomic (single DB transaction); files are
/// removed only after the transaction commits.
///
/// Reuses the offline engine's existing reads (`OutboxQueue.pendingJobs /
/// rejectedJobs / syncingJobs`) and its existing cleanup primitives
/// (`LocalStore.delete`, `OutboxQueue.removeForEntity`). No engine file is
/// modified.
class PurgeSyncedSegmentoUseCase {
  final Database _db;
  final SegmentoLocalStore _segmentoStore;
  final ImagenLocalStore _imagenStore;
  final VideoLocalStore _videoStore;
  final MensajeLocalStore _mensajeStore;
  final OutboxQueue _outbox;
  final LocalFileDeleter _deleteFile;
  final NetworkService _network;

  PurgeSyncedSegmentoUseCase({
    Database? db,
    SegmentoLocalStore? segmentoStore,
    ImagenLocalStore? imagenStore,
    VideoLocalStore? videoStore,
    MensajeLocalStore? mensajeStore,
    OutboxQueue? outbox,
    LocalFileDeleter? deleteFile,
    NetworkService? network,
  })  : _db = db ?? AppDI.database,
        _segmentoStore = segmentoStore ?? DI.get<SegmentoLocalStore>(),
        _imagenStore = imagenStore ?? DI.get<ImagenLocalStore>(),
        _videoStore = videoStore ?? DI.get<VideoLocalStore>(),
        _mensajeStore = mensajeStore ?? DI.get<MensajeLocalStore>(),
        _outbox = outbox ?? AppDI.outboxQueue,
        _deleteFile = deleteFile ?? _defaultDeleteFile,
        _network = network ?? AppDI.networkService;

  /// Reads the union of pending + rejected + syncing (non-delete) outbox jobs
  /// per entity type. Read FRESH for every segment, always AFTER enumerating
  /// that segment's dependents: a snapshot taken before the dependent read
  /// could miss a job enqueued in between (create is row+job atomic), and a
  /// dependent judged "synced" against a stale set would be purged with its
  /// un-uploaded file — see the batch-purge data-loss note below.
  Future<UnsyncedSets> readUnsyncedSets() async {
    Future<Set<String>> unsyncedFor(String entityType) async {
      final jobs = <SyncJob>[
        ...await _outbox.pendingJobs(entityType: entityType),
        ...await _outbox.rejectedJobs(entityType: entityType),
        ...await _outbox.syncingJobs(entityType: entityType),
      ];
      return {
        for (final j in jobs)
          if (j.operation != SyncOperation.delete) j.clientId,
      };
    }

    return UnsyncedSets(
      segmento: await unsyncedFor('segmento'),
      imagen: await unsyncedFor('imagen'),
      video: await unsyncedFor('video'),
      mensaje: await unsyncedFor('mensaje'),
    );
  }

  /// Pure predicate: the segment AND every dependent must be absent from the
  /// unsynced sets. Unit-testable in isolation (no I/O).
  static bool isFullySynced(
    SegmentoEntity s,
    List<ImagenSegmentoEntity> imgs,
    List<VideoSegmentoEntity> vids,
    List<MensajeSegmentoEntity> msgs,
    UnsyncedSets u,
  ) =>
      !u.segmento.contains(s.clientId) &&
      imgs.every((i) => !u.imagen.contains(i.clientId)) &&
      vids.every((v) => !u.video.contains(v.clientId)) &&
      msgs.every((m) => !u.mensaje.contains(m.clientId));

  /// Estados en los que el segmento deja de vivir en el móvil una vez cerrado
  /// en nube. El resto se queda: el operario sigue trabajándolo y el backend
  /// no lo devuelve en el pull (`GET /segmentos/contratista` solo sirve
  /// `propuesta` y `validada`), así que el móvil es la única copia.
  ///
  /// `contratista` sí purga: pasa a manos del gestor y vuelve al móvil cuando
  /// este la promueva a `validada`.
  static const Set<EstadoActividad> estadosQuePurgan = {
    EstadoActividad.finalizada,
    EstadoActividad.contratista,
  };

  /// Cierra [s] en nube si todo su contenido está subido y, solo si su estado
  /// es terminal ([estadosQuePurgan]), lo borra del móvil.
  ///
  /// Las dos cosas van separadas a propósito. El `sync-complete` es lo que
  /// marca las fotos/mensajes ya subidos como `complete` en backend y por
  /// tanto lo que los hace inmunes al `cleanupPendingChildren` del siguiente
  /// `upsert`; hay que llamarlo en CADA envío limpio, no solo en el último.
  /// El borrado local es otra decisión, y depende del estado de la actividad.
  ///
  /// Nunca borra a medias: si algún dependiente sigue sin subir, devuelve
  /// [PurgeStatus.keptUnsynced] y no toca nada (tampoco cierra: un sobre
  /// incompleto no puede figurar como transmitido).
  Future<PurgeOutcome> purgeIfFullySynced(SegmentoEntity s) async {
    // A segment never accepted by the backend cannot be fully synced.
    if (s.id == null) {
      return const PurgeOutcome(status: PurgeStatus.skippedNoRemoteId);
    }

    // Read dependents BEFORE the transaction (need .ruta + clientIds).
    final imgs =
        await _imagenStore.findWhere('segmento_client_id', s.clientId);
    final vids =
        await _videoStore.findWhere('segmento_client_id', s.clientId);
    // Mensajes por clientId del segmento (no por id remoto): un mensaje creado
    // con el segmento aún sin subir tiene segmento_id 0 y quedaría huérfano.
    final msgs =
        await _mensajeStore.findWhere('segmento_client_id', s.clientId);

    // Read the unsynced sets AFTER enumerating dependents so a job enqueued
    // between the two reads (row+job are atomic in OfflineRepository.create) is
    // always observed: any dependent present in `imgs/vids/msgs` had its job
    // committed before this read, so it cannot be missed and wrongly purged.
    final u = await readUnsyncedSets();
    if (!isFullySynced(s, imgs, vids, msgs, u)) {
      return const PurgeOutcome(status: PurgeStatus.keptUnsynced);
    }

    // Envío finalizado: informa al backend de que TODO el contenido del
    // segmento (datos + imágenes + vídeos + mensajes) está subido, ANTES de
    // borrar local. Si falla, no se borra nada y se reintenta en el próximo
    // envío. Idempotente por id: reintentar sobre un segmento ya finalizado
    // devuelve 2xx.
    if (!await _notifySyncComplete(s)) {
      return const PurgeOutcome(status: PurgeStatus.finalizeFailed);
    }

    // Frontera de cierre: todo lo entregado hasta este instante está `complete`
    // en backend. Se graba el `max(synced_at)` de los jobs del sobre, no
    // `DateTime.now()`, para que ambos lados de la comparación vengan de la
    // misma fuente (ver `SegmentoLocalStore.markSyncConfirmed`).
    await _segmentoStore.markSyncConfirmed(
      s.clientId,
      await _maxSyncedAt(s, imgs, vids, msgs),
    );

    if (!estadosQuePurgan.contains(s.estado)) {
      return const PurgeOutcome(status: PurgeStatus.finalizedKept);
    }

    // Atomic cascade: any failure rolls the whole thing back — never a
    // half-deleted segment.
    await _db.transaction((txn) async {
      await _segmentoStore.delete(s.clientId, txn: txn);
      await _outbox.removeForEntity(
        entityType: 'segmento',
        clientId: s.clientId,
        txn: txn,
      );
      for (final i in imgs) {
        await _imagenStore.delete(i.clientId, txn: txn);
        await _outbox.removeForEntity(
          entityType: 'imagen',
          clientId: i.clientId,
          txn: txn,
        );
      }
      for (final v in vids) {
        await _videoStore.delete(v.clientId, txn: txn);
        await _outbox.removeForEntity(
          entityType: 'video',
          clientId: v.clientId,
          txn: txn,
        );
      }
      for (final m in msgs) {
        await _mensajeStore.delete(m.clientId, txn: txn);
        await _outbox.removeForEntity(
          entityType: 'mensaje',
          clientId: m.clientId,
          txn: txn,
        );
      }
    });

    // Files removed only AFTER a successful commit; mensajes have no file.
    final deleted = <String>[];
    for (final i in imgs) {
      if (i.ruta.isNotEmpty) {
        await _deleteFile(i.ruta);
        deleted.add(i.ruta);
      }
    }
    for (final v in vids) {
      if (v.ruta.isNotEmpty) {
        await _deleteFile(v.ruta);
        deleted.add(v.ruta);
      }
    }

    return PurgeOutcome(
      status: PurgeStatus.purged,
      imagenes: imgs.length,
      videos: vids.length,
      mensajes: msgs.length,
      filesDeleted: deleted,
    );
  }

  /// Instante de entrega más reciente del sobre, en epoch ms.
  ///
  /// Cae a `DateTime.now()` solo si NINGÚN job del sobre tiene `synced_at`, lo
  /// que en la práctica no ocurre (para llegar aquí el sobre está entero
  /// entregado); el fallback evita escribir `null` y dejar la frontera abierta.
  Future<int> _maxSyncedAt(
    SegmentoEntity s,
    List<ImagenSegmentoEntity> imgs,
    List<VideoSegmentoEntity> vids,
    List<MensajeSegmentoEntity> msgs,
  ) async {
    final ambitos = <String, Set<String>>{
      'segmento': {s.clientId},
      'imagen': imgs.map((i) => i.clientId).toSet(),
      'video': vids.map((v) => v.clientId).toSet(),
      'mensaje': msgs.map((m) => m.clientId).toSet(),
    };
    var max = 0;
    for (final entry in ambitos.entries) {
      if (entry.value.isEmpty) continue;
      final jobs = await _outbox.syncedJobs(entityType: entry.key);
      for (final j in jobs) {
        final at = j.syncedAt?.millisecondsSinceEpoch;
        if (at != null && entry.value.contains(j.clientId) && at > max) {
          max = at;
        }
      }
    }
    return max > 0 ? max : DateTime.now().millisecondsSinceEpoch;
  }

  /// `clientId`s del sobre que subieron en un intento que nadie cerró: su job
  /// está `synced` pero es posterior al último `sync-complete` confirmado.
  ///
  /// Son exactamente las filas que el backend tiene en
  /// `estadotransmision='pending'` y que `cleanupPendingChildren` borrará en
  /// cuanto salga un `upsert` de este segmento. Reenviar cualquier otra cosa
  /// duplicaría contenido: la API ya no deduplica por `client_id`.
  Future<Set<String>> unconfirmedChildIds({
    required String segmentoClientId,
    required String entityType,
    required Set<String> candidatos,
  }) async {
    if (candidatos.isEmpty) return const <String>{};
    final frontera = await _segmentoStore.readSyncConfirmedAt(segmentoClientId);
    final jobs = await _outbox.syncedJobs(entityType: entityType);
    return {
      for (final j in jobs)
        if (candidatos.contains(j.clientId) &&
            j.syncedAt != null &&
            (frontera == null ||
                j.syncedAt!.millisecondsSinceEpoch > frontera))
          j.clientId,
    };
  }

  /// POSTs `sync-complete` for [s]. Returns true on a 2xx response, false on
  /// any non-success status or network error (so the caller keeps the segment
  /// for a later retry). Idempotent server-side by segment id.
  Future<bool> _notifySyncComplete(SegmentoEntity s) async {
    try {
      // Sin body y sin Bearer: §7 define el endpoint sin cuerpo (el id viaja en
      // el path) y §1 fija el HMAC como única autenticación de la API. Los
      // campos que se mandaban no están declarados en el backend: ajv los
      // borraba en silencio y respondía 200 igual.
      final response =
          await _network.post(ApiEndpoints.segmentoSyncComplete(s.id!));
      if (response.isSuccess && !bodyIndicatesError(response.data)) return true;
      final msg = bodyErrorMessage(response.data);
      AppLog.w(
        'PurgeSyncedSegmentoUseCase: sync-complete rechazado '
        '(segmento ${s.id}, HTTP ${response.statusCode}'
        '${msg != null ? ', "$msg"' : ''}) — no se purga.',
      );
      return false;
    } on NetworkError catch (e, st) {
      AppLog.w(
        'PurgeSyncedSegmentoUseCase: sync-complete falló por red '
        '(segmento ${s.id}) — no se purga.',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Batch variant. Each segment is evaluated with its own FRESH unsynced-set
  /// read (inside [purgeIfFullySynced]); the loop never shares a pre-read
  /// snapshot. Reusing one snapshot across the batch would race the operator
  /// capturing new media/messages while the loop runs — a row created after the
  /// snapshot but before its segment is reached would be judged synced and
  /// purged with its un-uploaded file. Correctness over the extra reads.
  Future<List<PurgeOutcome>> purgeAllFullySynced(
    List<SegmentoEntity> list,
  ) async {
    final outcomes = <PurgeOutcome>[];
    for (final s in list) {
      outcomes.add(await purgeIfFullySynced(s));
    }
    return outcomes;
  }
}
