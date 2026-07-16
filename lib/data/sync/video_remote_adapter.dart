import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_endpoints.dart';
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
/// 2. **Chunks** — `PATCH /api/enagas/v1/videos/upload/{uploadId}` with
///    `Upload-Offset` header and raw binary body (5 MB default).
///    Per-chunk intra-adapter retry (max 3 attempts, retryable errors only).
///    Server offset re-confirmed via GET status before each retry.
/// 3. **Complete** — `POST /api/enagas/v1/videos/upload/{uploadId}/complete`.
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
  static const int _chunkSize = 5 * 1024 * 1024; // 5 MB
  // ponytail: retry acotado, techo 3, subir si hace falta
  static const int _maxChunkRetries = 3;

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

      // ── Step 1: Resolve or init upload session ──────────────────────────
      String uploadId;
      int offset;

      if (entity.uploadId != null) {
        // Attempt to resume an existing session.
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
              final resp = await _network.patchVideoChunk(
                uploadId: uploadId,
                uploadOffset: offset,
                bytes: chunkBytes,
              );
              final body = _asMap(resp.data);
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

      // ── Step 3: Complete ────────────────────────────────────────────────
      await _network.completeVideoUpload(uploadId);

      // ── Step 4: Return success ──────────────────────────────────────────
      return _buildSuccess(entity, uploadId, totalBytes);
    } on NetworkError catch (e) {
      return _mapNetworkError(e);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Calls `initVideoUpload`, persists [uploadId] to the store, and returns
  /// `(uploadId, offset)`. May throw [NetworkError] on server error.
  Future<(String, int)> _doInit({
    required VideoSegmentoEntity entity,
    required int totalBytes,
    required String mimeType,
    required String usuario,
    required int userId,
  }) async {
    final resp = await _network.initVideoUpload({
      'original_filename': entity.filename,
      'total_bytes': totalBytes,
      'mime_type': mimeType,
      'client_id': entity.clientId,
      'segmento_id': entity.segmentoId,
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
    int totalBytes,
  ) {
    final result = entity.copyWith(
      url: ApiEndpoints.videoDownload(uploadId),
      subidaAt: DateTime.now(),
      uploadOffset: 0,
    )..uploadId = uploadId;
    return SyncSuccess<VideoSegmentoEntity>(
      remoteId: uploadId,
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
