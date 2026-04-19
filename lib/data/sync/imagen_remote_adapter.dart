import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/sync/contracts/remote_adapter.dart';
import '../../core/sync/contracts/sync_job.dart' show SyncOperation;
import '../../domain/entities/imagen_segmento_entity.dart';
import '../network/network_error.dart';
import '../network/network_file.dart';
import '../network/network_service.dart';
import '../network/sync_outcome_from_network_error.dart';

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
  static const String _path = '/operador/additem';
  static const String _fileFieldName = 'file';
  static const String _tokenKey = 'auth_token';
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
      final token = await _secureStorage.read(key: _tokenKey);
      final prefs = await SharedPreferences.getInstance();
      final usuario = prefs.getString(_prefsUsuarioKey) ?? '';
      final userId = prefs.getInt(_prefsUserIdKey)?.toString() ?? '0';

      final file = _fileFactory(entity.localPath);
      final fileName = file.path.split('/').last;

      final bytes = await file.openRead().first;
      final mimeType = _detectMime(bytes);

      final fields = <String, dynamic>{
        'fileNameOriginal': fileName,
        'description': entity.tipoFoto == TipoFoto.antes
            ? 'Antes del trabajo'
            : 'Después del trabajo',
        'tipo': 'imagen',
        'tipovigilancia': 'VH',
        'usuariologged': usuario,
        'idusuariologged': userId,
        'actividadId': entity.actividadId.toString(),
        if (entity.segmentoId != null)
          'segmentoId': entity.segmentoId.toString(),
        'tipoFoto': entity.tipoFoto.name,
      };

      final files = <NetworkFile>[
        NetworkFile(
          fieldName: _fileFieldName,
          filePath: entity.localPath,
          filename: fileName,
          contentType: mimeType,
        ),
      ];

      final headers = <String, String>{
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final response = await _network.postMultipart(
        _path,
        fields: fields,
        files: files,
        headers: headers,
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

      final remoteIntId = _extractRemoteIntId(payload);
      final remoteUrl = _extractRemoteUrl(payload);

      final updated = ImagenSegmentoEntity(
        localId: entity.localId,
        remoteIntId: remoteIntId ?? entity.remoteIntId,
        actividadId: entity.actividadId,
        segmentoId: entity.segmentoId,
        localPath: entity.localPath,
        remoteUrl: remoteUrl ?? entity.remoteUrl,
        tipoFoto: entity.tipoFoto,
        capturedAt: entity.capturedAt,
        latitude: entity.latitude,
        longitude: entity.longitude,
        syncStatus: SyncStatus.uploaded,
      );

      return SyncSuccess<ImagenSegmentoEntity>(
        remoteId: remoteIntId?.toString(),
        serverVersion: updated,
      );
    } on NetworkError catch (e) {
      return syncOutcomeFromNetworkError<ImagenSegmentoEntity>(e);
    }
  }

  int? _extractRemoteIntId(Map<String, dynamic> payload) {
    for (final key in const ['id', 'remote_id', 'remoteId', 'itemId']) {
      final value = payload[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  String? _extractRemoteUrl(Map<String, dynamic> payload) {
    for (final key in const ['url', 'remote_url', 'remoteUrl']) {
      final value = payload[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  String _detectMime(List<int> bytes) {
    if (bytes.length >= 4) {
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'image/jpeg';
      if (bytes[0] == 0x89 && bytes[1] == 0x50) return 'image/png';
    }
    return 'image/jpeg';
  }
}
