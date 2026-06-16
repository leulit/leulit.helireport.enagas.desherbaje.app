import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_endpoints.dart';
import '../../core/sync/contracts/remote_adapter.dart';
import '../../core/sync/contracts/sync_job.dart' show SyncOperation;
import '../../domain/entities/imagen_segmento_entity.dart';
import '../network/network_error.dart';
import '../network/network_file.dart';
import '../network/network_service.dart';
import '../network/sync_outcome_from_network_error.dart';
import 'adapter_support.dart';

/// Remote adapter for [ImagenSegmentoEntity].
///
/// Replicates the exact multipart contract produced by the legacy
/// `ImageUploadProvider.uploadImage`:
/// - endpoint: `POST /operador/additem`
/// - bearer token read from `flutter_secure_storage` under `auth_token`
/// - `usuariologged` / `idusuariologged` read from `SharedPreferences`
/// - file attached under the field name `file`
///
/// Only [SyncOperation.create] is supported — the backend assigns the remote
/// id on upload. Updates and deletes return [SyncUnrecoverable] so the outbox
/// can mark the job dead and surface it to the user.
class ImagenRemoteAdapter extends RemoteAdapter<ImagenSegmentoEntity> {
  static const String _fileFieldName = 'file';
  static const String _prefsUsuarioKey = 'user_usuario';
  static const String _prefsUserIdKey = 'user_id';

  final NetworkService _network;
  final File Function(String path) _fileFactory;
  final FlutterSecureStorage _secureStorage;

  ImagenRemoteAdapter(
    this._network, {
    File Function(String path) fileFactory = File.new,
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  })  : _fileFactory = fileFactory,
        _secureStorage = secureStorage;

  @override
  Future<SyncOutcome<ImagenSegmentoEntity>> push({
    required ImagenSegmentoEntity entity,
    required SyncOperation operation,
  }) async {
    if (operation != SyncOperation.create) {
      return SyncUnrecoverable<ImagenSegmentoEntity>(
        'Operation not supported for ImagenSegmentoEntity: ${operation.name}',
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final usuario = prefs.getString(_prefsUsuarioKey) ?? '';
      final userId = prefs.getInt(_prefsUserIdKey)?.toString() ?? '0';

      final file = _fileFactory(entity.ruta);
      final fileName = file.path.split('/').last;

      final headerBytes = await _readHeader(file, 12);
      final mimeType = _detectMime(headerBytes, fileName: fileName);

      final fields = <String, dynamic>{
        'fileNameOriginal': fileName,
        'description': entity.tipoFoto == TipoFoto.antes
            ? 'Antes del trabajo'
            : 'Después del trabajo',
        'tipo': 'imagen',
        'tipovigilancia': 'VH',
        'usuariologged': usuario,
        'idusuariologged': userId,
        'clientId': entity.clientId,
        'actividadId': entity.actividadId.toString(),
        'segmentoId': entity.segmentoId.toString(),
        'tipoFoto': entity.tipoFoto.name,
      };

      final files = <NetworkFile>[
        NetworkFile(
          fieldName: _fileFieldName,
          filePath: entity.ruta,
          filename: fileName,
          contentType: mimeType,
        ),
      ];

      final response = await _network.postMultipart(
        ApiEndpoints.imagenAdd,
        fields: fields,
        files: files,
        headers: await bearerAuthHeader(_secureStorage),
      );

      if (!response.isSuccess) {
        return SyncUnrecoverable<ImagenSegmentoEntity>(
          'Unexpected status: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final data = response.data;
      final payload = data is Map<String, dynamic>
          ? data
          : data is Map
              ? data.cast<String, dynamic>()
              : const <String, dynamic>{};

      final remoteIntId = extractRemoteIntId(payload);
      final remoteUrl = _extractRemoteUrl(payload);

      final updated = entity.copyWith(
        url: remoteUrl ?? entity.url,
        subidaAt: DateTime.now(),
      );
      if (remoteIntId != null) updated.id = remoteIntId;

      return SyncSuccess<ImagenSegmentoEntity>(
        remoteId: remoteIntId?.toString() ?? entity.id?.toString(),
        serverVersion: updated,
      );
    } on NetworkError catch (e) {
      return syncOutcomeFromNetworkError<ImagenSegmentoEntity>(e);
    }
  }

  String? _extractRemoteUrl(Map<String, dynamic> payload) {
    for (final key in const ['url', 'remote_url', 'remoteUrl']) {
      final value = payload[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  /// Accumulates chunks from `file.openRead(0, maxBytes)` until at least
  /// [maxBytes] have been collected or the stream is exhausted.
  ///
  /// This is necessary because a single `openRead().first` only yields the
  /// first chunk (often 4 KB), but a very small file may emit fewer than
  /// [maxBytes] bytes total in multiple smaller chunks. We accumulate to
  /// guarantee ≥ [maxBytes] bytes for reliable magic-byte detection.
  @visibleForTesting
  Future<List<int>> readHeader(File file, int maxBytes) =>
      _readHeader(file, maxBytes);

  Future<List<int>> _readHeader(File file, int maxBytes) async {
    final accumulated = <int>[];
    await for (final chunk in file.openRead(0, maxBytes)) {
      accumulated.addAll(chunk);
      if (accumulated.length >= maxBytes) break;
    }
    return accumulated;
  }

  /// Detects the MIME type from binary magic bytes.
  ///
  /// Falls back to the file extension when the header is too short or unknown,
  /// and ultimately defaults to `image/jpeg` if nothing matches.
  @visibleForTesting
  String detectMime(List<int> bytes, {String? fileName}) =>
      _detectMime(bytes, fileName: fileName);

  String _detectMime(List<int> bytes, {String? fileName}) {
    if (bytes.length >= 4) {
      // JPEG: FF D8 FF
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return 'image/jpeg';
      }
      // PNG: 89 50 4E 47
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return 'image/png';
      }
      // GIF: 47 49 46 38
      if (bytes[0] == 0x47 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x38) {
        return 'image/gif';
      }
      // WebP: RIFF (52 49 46 46) ... WEBP at bytes[8..11]
      if (bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return 'image/webp';
      }
    }

    // Fallback: extension-based
    if (fileName != null) {
      final ext = fileName.split('.').last.toLowerCase();
      switch (ext) {
        case 'jpg':
        case 'jpeg':
          return 'image/jpeg';
        case 'png':
          return 'image/png';
        case 'gif':
          return 'image/gif';
        case 'webp':
          return 'image/webp';
        case 'heic':
        case 'heif':
          return 'image/heic';
      }
    }

    return 'image/jpeg';
  }
}
