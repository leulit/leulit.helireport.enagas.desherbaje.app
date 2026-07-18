import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_endpoints.dart';
import '../../core/app_log.dart';
import '../../core/sync/contracts/remote_adapter.dart';
import '../../core/sync/contracts/sync_job.dart' show SyncOperation;
import '../../domain/entities/video_segmento_entity.dart';
import '../network/network_error.dart';
import '../network/network_service.dart';
import 'adapter_support.dart';
import 'video_local_store.dart';

/// Remote adapter for [VideoSegmentoEntity].
///
/// Implements a TUS-like resumable chunked upload protocol:
/// 1. **Init** — `POST /api/enagas/v1/videos/upload` → `uploadId`.
///    Persists [uploadId] to [VideoLocalStore] immediately so the session
///    survives an app restart.
/// 2. **Chunks** — `POST /api/enagas/v1/videos/upload/{uploadId}` with
///    `Upload-Offset` header and raw binary body (5 MB default).
///    Per-chunk intra-adapter retry (max 3 attempts, retryable errors only).
///    Server offset re-confirmed via GET status before each retry.
///    Un `409 { offset }` (§6.2) no es un fallo: es el servidor diciendo que va
///    por delante; se adopta ese offset y se sigue.
/// 3. **Complete** — `POST /api/enagas/v1/videos/upload/{uploadId}/complete`.
///    Un `409 { offset, totalBytes }` (§6.4) significa que faltan bytes: se
///    reanudan los chunks desde ese offset y se reintenta el cierre.
///    MOV→MP4 conversion is asynchronous on the backend.
///
/// Authentication uses only the new HMAC scheme (X-HMAC-Signature / X-Timestamp,
/// timestamp in **ms**). No Bearer token. 401/403 = bad HMAC signature →
/// [SyncUnrecoverable], NOT [AuthExpiredException] (which would log the user out).
///
/// Only [SyncOperation.create] is supported. Update and delete return
/// [SyncUnrecoverable] immediately.
class VideoRemoteAdapter extends RemoteAdapter<VideoSegmentoEntity> {
  static const String _prefsUsuarioKey = 'user_usuario';
  static const String _prefsUserIdKey = 'user_id';
  // Límites del backend (§6): chunk 10 MB, fichero 2 GB.
  static const int _chunkSize = 5 * 1024 * 1024; // 5 MB
  static const int _maxFileBytes = 2 * 1024 * 1024 * 1024; // 2 GB
  // ponytail: retry acotado, techo 3, subir si hace falta
  static const int _maxChunkRetries = 3;

  /// Techo de reanudaciones por 409 en una misma subida. Sin él, un servidor
  /// que repita offset dejaría el bucle girando para siempre.
  static const int _maxResumeRounds = 5;

  final NetworkService _network;
  final VideoLocalStore _store;

  VideoRemoteAdapter(this._network, this._store);

  @override
  Future<SyncOutcome<VideoSegmentoEntity>> push({
    required VideoSegmentoEntity entity,
    required SyncOperation operation,
  }) async {
    if (operation != SyncOperation.create) {
      return SyncUnrecoverable<VideoSegmentoEntity>(
        'Operation not supported for VideoSegmentoEntity: ${operation.name}',
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final usuario = prefs.getString(_prefsUsuarioKey) ?? '';
      final userId = prefs.getInt(_prefsUserIdKey) ?? 0;

      final file = File(entity.ruta);
      final totalBytes = entity.tamanyoBytes ?? await file.length();
      final mimeType = _mimeForExtension(entity.filename);

      if (totalBytes > _maxFileBytes) {
        return SyncUnrecoverable<VideoSegmentoEntity>(
          'Vídeo de $totalBytes bytes: supera el límite del backend '
          '($_maxFileBytes bytes)',
        );
      }

      // ── Step 1: Resolve or init upload session ──────────────────────────
      String uploadId;
      int offset;

      if (entity.uploadId != null) {
        // Reanudación DENTRO del intento en curso (corte de red, reinicio de
        // app). Un `uploadId` persistido solo llega hasta aquí si pertenece al
        // intento vigente: quien entrega un `upsert` —y por tanto anula el
        // intento anterior en el backend (§2 regla 2)— borra antes las sesiones
        // de vídeo de ese segmento (VideoLocalStore.clearUploadSessions), así
        // que un sobre reenviado entra siempre por la rama del `init`. Sin esa
        // invariante, el `complete: true` de abajo devolvería éxito sobre bytes
        // que el backend ya borró.
        try {
          final statusResp = await _network.getVideoStatus(entity.uploadId!);
          final statusBody = _asMap(statusResp.data);
          if (statusBody['complete'] == true) {
            // Already completed — idempotent success.
            return _buildSuccess(entity, entity.uploadId!, totalBytes);
          }
          uploadId = entity.uploadId!;
          offset = (statusBody['offset'] as num?)?.toInt() ?? 0;
        } on NetworkError catch (e) {
          if (e.statusCode == 404) {
            // Session expired or lost on the server — re-init from scratch.
            final r = await _doInit(
              entity: entity,
              totalBytes: totalBytes,
              mimeType: mimeType,
              usuario: usuario,
              userId: userId,
            );
            uploadId = r.$1;
            offset = r.$2;
          } else {
            return _mapNetworkError(e);
          }
        }
      } else {
        // No session yet — init a new one.
        final r = await _doInit(
          entity: entity,
          totalBytes: totalBytes,
          mimeType: mimeType,
          usuario: usuario,
          userId: userId,
        );
        uploadId = r.$1;
        offset = r.$2;
      }

      // ── Step 2: Send chunks ─────────────────────────────────────────────
      await _uploadChunks(
        file: file,
        entity: entity,
        uploadId: uploadId,
        startOffset: offset,
        totalBytes: totalBytes,
      );

      // ── Step 3: Complete (con reanudación por 409, §6.4) ────────────────
      Map<String, dynamic> completeBody;
      int resumeRounds = 0;
      int? lastResumeOffset;
      while (true) {
        final completeResp = await _network.completeVideoUpload(uploadId);
        if (completeResp.statusCode != 409) {
          completeBody = _asMap(completeResp.data);
          break;
        }

        // §6.4: 409 sin clave `error` = faltan bytes desde `offset`.
        final serverOffset =
            (_asMap(completeResp.data)['offset'] as num?)?.toInt();
        resumeRounds++;
        if (serverOffset == null ||
            serverOffset == lastResumeOffset ||
            resumeRounds > _maxResumeRounds) {
          return SyncUnrecoverable<VideoSegmentoEntity>(
            'Cierre de vídeo atascado: el servidor pide reanudar en '
            '$serverOffset tras $resumeRounds intentos',
            statusCode: 409,
          );
        }
        lastResumeOffset = serverOffset;
        AppLog.w(
          'Complete devolvió 409: faltan bytes, reanudando en $serverOffset '
          '(uploadId $uploadId)',
        );
        await _uploadChunks(
          file: file,
          entity: entity,
          uploadId: uploadId,
          startOffset: serverOffset,
          totalBytes: totalBytes,
        );
      }

      // ── Step 4: Return success ──────────────────────────────────────────
      // §6.4 devuelve `id` = fila de `imagenes_segmento`; es la identidad
      // remota del vídeo y la que sirve su media (§9).
      final videoRecordId = extractRemoteIntId(completeBody);

      return _buildSuccess(entity, uploadId, totalBytes,
          videoRecordId: videoRecordId);
    } on NetworkError catch (e) {
      return _mapNetworkError(e);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Envía el fichero por chunks desde [startOffset] hasta [totalBytes].
  ///
  /// El offset del siguiente chunk es SIEMPRE el que confirma el servidor
  /// (`200 { offset }`), nunca un contador local. Un `409 { offset }` (§6.2)
  /// significa que el servidor va por delante: se adopta su offset y se sigue.
  /// Propaga [NetworkError] cuando no hay forma de avanzar.
  Future<void> _uploadChunks({
    required File file,
    required VideoSegmentoEntity entity,
    required String uploadId,
    required int startOffset,
    required int totalBytes,
  }) async {
    int offset = startOffset;
    int resumeRounds = 0;
    int? lastResumeOffset;

    final raf = await file.open();
    try {
      while (offset < totalBytes) {
        final end = (offset + _chunkSize).clamp(0, totalBytes);
        await raf.setPosition(offset);
        final chunkBytes = await raf.read(end - offset);

        bool chunkDone = false;
        for (int attempt = 0; attempt < _maxChunkRetries && !chunkDone; attempt++) {
          if (attempt > 0) {
            // Back-off: 200ms, 400ms.
            await Future<void>.delayed(
              Duration(milliseconds: 200 * attempt),
            );
            // Re-check server offset before retrying (server may have partial).
            try {
              final st = await _network.getVideoStatus(uploadId);
              final stMap = _asMap(st.data);
              final serverOff = (stMap['offset'] as num?)?.toInt();
              if (serverOff != null && serverOff > offset) {
                offset = serverOff;
                chunkDone = true; // server already has these bytes
                break;
              }
            } on NetworkError {
              // Status check failed — retry chunk from current offset.
            }
          }

          if (chunkDone) break;

          try {
            final resp = await _network.postVideoChunk(
              uploadId: uploadId,
              uploadOffset: offset,
              bytes: chunkBytes,
            );
            final body = _asMap(resp.data);

            if (resp.statusCode == 409) {
              // §6.2: 409 sin clave `error` = el servidor está por delante del
              // offset enviado. Se adopta el suyo y se reanuda desde ahí.
              final serverOffset = (body['offset'] as num?)?.toInt();
              resumeRounds++;
              if (serverOffset == null ||
                  serverOffset == lastResumeOffset ||
                  resumeRounds > _maxResumeRounds) {
                throw NetworkError(
                  category: NetworkErrorCategory.unrecoverable,
                  statusCode: 409,
                  message: 'Subida de vídeo atascada: el servidor repite '
                      'offset $serverOffset tras $resumeRounds reanudaciones',
                );
              }
              lastResumeOffset = serverOffset;
              offset = serverOffset;
              AppLog.w(
                'Chunk devolvió 409: servidor por delante, reanudando en '
                '$serverOffset (uploadId $uploadId)',
              );
              unawaited(_store.saveUploadOffset(entity.clientId, offset));
              chunkDone = true;
              break;
            }

            offset = (body['offset'] as num?)?.toInt() ?? end;
            // fire-and-forget: best-effort persistence of offset for UI
            unawaited(_store.saveUploadOffset(entity.clientId, offset));
            chunkDone = true;
          } on NetworkError catch (e) {
            final retryable = e.category == NetworkErrorCategory.offline ||
                e.category == NetworkErrorCategory.timeout ||
                e.category == NetworkErrorCategory.retryable;
            if (!retryable || attempt == _maxChunkRetries - 1) rethrow;
          }
        }
      }
    } finally {
      await raf.close();
    }
  }

  /// Calls `initVideoUpload`, persists [uploadId] to the store, and returns
  /// `(uploadId, offset)`. May throw [NetworkError] on server error.
  Future<(String, int)> _doInit({
    required VideoSegmentoEntity entity,
    required int totalBytes,
    required String mimeType,
    required String usuario,
    required int userId,
  }) async {
    // §6.1: nombres exactos en camelCase. Cualquier campo no declarado lo borra
    // ajv en silencio (200 igualmente), así que mandar `id`/`clientId` solo
    // despistaría al siguiente lector.
    final resp = await _network.initVideoUpload({
      'originalFilename': entity.filename,
      'totalBytes': totalBytes,
      'mimeType': mimeType,
      'segmentoId': entity.segmentoId,
      'tipoFoto': entity.tipoVideo.valor,
      'usuariologged': usuario,
      'idusuariologged': userId,
    });

    final body = _asMap(resp.data);
    if (bodyIndicatesError(resp.data)) {
      throw NetworkError(
        category: NetworkErrorCategory.unrecoverable,
        message: bodyErrorMessage(resp.data) ?? 'Init de vídeo rechazado',
      );
    }
    final uploadId = body['uploadId'] as String?;
    if (uploadId == null || uploadId.isEmpty) {
      throw NetworkError(
        category: NetworkErrorCategory.unrecoverable,
        message:
            'Server did not return uploadId on init (response: $body)',
      );
    }

    final offset = (body['offset'] as num?)?.toInt() ?? 0;
    // Persist immediately so resume works after an app restart.
    await _store.saveUploadId(entity.clientId, uploadId);
    return (uploadId, offset);
  }

  SyncSuccess<VideoSegmentoEntity> _buildSuccess(
    VideoSegmentoEntity entity,
    String uploadId,
    int totalBytes, {
    int? videoRecordId,
  }) {
    // §9: toda la media (fotos y vídeos) se sirve por `thumbdb/{id}/{w}/{h}`,
    // indexada por el id de la fila de `imagenes_segmento`, no por `uploadId`.
    final recordId = videoRecordId ?? entity.id;
    final result = entity.copyWith(
      url: recordId == null ? null : ApiEndpoints.segmentoThumb(recordId, 0, 0),
      subidaAt: DateTime.now(),
      uploadOffset: 0,
    )..uploadId = uploadId;
    if (videoRecordId != null) result.id = videoRecordId;
    return SyncSuccess<VideoSegmentoEntity>(
      remoteId: videoRecordId?.toString() ?? uploadId,
      serverVersion: result,
    );
  }

  /// Maps a [NetworkError] to a [SyncOutcome].
  ///
  /// Video endpoints use HMAC auth, not Bearer. 401/403 means the signature was
  /// rejected — this is a configuration/bug issue, NOT an expired session.
  /// We return [SyncUnrecoverable] and do NOT throw [AuthExpiredException].
  SyncOutcome<VideoSegmentoEntity> _mapNetworkError(NetworkError e) {
    return switch (e.category) {
      NetworkErrorCategory.offline ||
      NetworkErrorCategory.timeout ||
      NetworkErrorCategory.retryable =>
        SyncRetryable<VideoSegmentoEntity>(
          '${e.category.name}: ${e.message}',
        ),
      NetworkErrorCategory.unauthorized =>
        SyncUnrecoverable<VideoSegmentoEntity>(
          e.statusCode == 401
              ? 'HMAC signature rejected (HTTP 401) — '
                  'check X-HMAC-Signature calculation'
              : 'HMAC signature rejected (HTTP 403) — '
                  'check X-HMAC-Signature calculation',
          statusCode: e.statusCode,
        ),
      _ => SyncUnrecoverable<VideoSegmentoEntity>(
          e.message,
          statusCode: e.statusCode,
        ),
    };
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  /// Detects MIME type from file extension.
  ///
  /// Android records `.mp4` (`video/mp4`); iOS records `.mov` (`video/quicktime`).
  /// The backend remuxes `.mov→.mp4` with `ffmpeg -c copy` (no re-encode).
  @visibleForTesting
  String mimeForExtension(String filename) => _mimeForExtension(filename);

  String _mimeForExtension(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'mp4'  => 'video/mp4',
      'mov'  => 'video/quicktime',
      'm4v'  => 'video/x-m4v',
      'avi'  => 'video/x-msvideo',
      'webm' => 'video/webm',
      _      => 'video/mp4',
    };
  }
}
