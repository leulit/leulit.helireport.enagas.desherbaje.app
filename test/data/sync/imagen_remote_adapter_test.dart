import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helireport_desherbaje/core/sync/contracts/remote_adapter.dart';
import 'package:helireport_desherbaje/core/sync/contracts/sync_job.dart'
    show SyncOperation;
import 'package:helireport_desherbaje/data/network/network_error.dart';
import 'package:helireport_desherbaje/data/network/network_file.dart';
import 'package:helireport_desherbaje/data/network/network_response.dart';
import 'package:helireport_desherbaje/data/network/network_service.dart';
import 'package:helireport_desherbaje/data/sync/imagen_remote_adapter.dart';
import 'package:helireport_desherbaje/domain/entities/imagen_segmento_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  final String? token;
  const _FakeSecureStorage({this.token});

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return token;
  }
}

class _FakeNetworkService extends NetworkService {
  NetworkResponse<dynamic>? response;
  NetworkError? error;

  Map<String, dynamic>? capturedFields;
  List<NetworkFile>? capturedFiles;
  Map<String, String>? capturedHeaders;
  String? capturedPath;
  int callCount = 0;

  // Skip Dio initialisation — we never hit the wire.
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<NetworkResponse<dynamic>> postMultipart(
    String path, {
    required Map<String, dynamic> fields,
    required List<NetworkFile> files,
    Map<String, String>? headers,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    callCount++;
    capturedPath = path;
    capturedFields = fields;
    capturedFiles = files;
    capturedHeaders = headers;
    if (error != null) throw error!;
    return response!;
  }
}

Future<File> _writeTmpImage(String name) async {
  final file = File(
    '${Directory.systemTemp.path}/imagen_remote_adapter_test_$name.jpg',
  );
  // JPEG magic bytes so the MIME detector returns image/jpeg.
  final bytes = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

ImagenSegmentoEntity _makeImagen({
  required String localId,
  required String localPath,
  int actividadId = 501,
  int? segmentoId = 77,
  TipoFoto tipoFoto = TipoFoto.antes,
  DateTime? capturedAt,
}) {
  return ImagenSegmentoEntity(
    localId: localId,
    actividadId: actividadId,
    segmentoId: segmentoId,
    localPath: localPath,
    tipoFoto: tipoFoto,
    capturedAt: capturedAt ?? DateTime(2026, 4, 19, 12, 0, 0),
    latitude: 40.1,
    longitude: -3.5,
    syncStatus: SyncStatus.pending,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'user_usuario': 'operator.x',
      'user_id': 42,
    });
  });

  group('ImagenRemoteAdapter.push — create', () {
    test('on success returns SyncSuccess with remoteId and uploaded serverVersion',
        () async {
      final tmp = await _writeTmpImage('success');
      addTearDown(() async {
        if (tmp.existsSync()) await tmp.delete();
      });

      final network = _FakeNetworkService()
        ..response = NetworkResponse<dynamic>(
          statusCode: 200,
          data: <String, dynamic>{
            'id': 999,
            'url': 'https://cdn.example.com/img/999.jpg',
          },
        );

      final adapter = ImagenRemoteAdapter(
        network,
        secureStorage: const _FakeSecureStorage(token: 'abc-token'),
      );

      final entity = _makeImagen(
        localId: 'uuid-ok',
        localPath: tmp.path,
        tipoFoto: TipoFoto.despues,
      );

      final outcome = await adapter.push(
        entity: entity,
        operation: SyncOperation.create,
      );

      expect(outcome, isA<SyncSuccess<ImagenSegmentoEntity>>());
      final success = outcome as SyncSuccess<ImagenSegmentoEntity>;
      expect(success.remoteId, '999');
      expect(success.serverVersion, isNotNull);
      expect(success.serverVersion!.remoteIntId, 999);
      expect(
        success.serverVersion!.remoteUrl,
        'https://cdn.example.com/img/999.jpg',
      );
      expect(success.serverVersion!.syncStatus, SyncStatus.uploaded);
      expect(success.serverVersion!.localId, 'uuid-ok');
      expect(success.serverVersion!.actividadId, 501);
      expect(success.serverVersion!.tipoFoto, TipoFoto.despues);

      // Contract check: match the legacy provider's multipart shape exactly.
      expect(network.callCount, 1);
      expect(network.capturedPath, '/operador/additem');
      expect(network.capturedFields!['tipo'], 'imagen');
      expect(network.capturedFields!['tipovigilancia'], 'VH');
      expect(network.capturedFields!['usuariologged'], 'operator.x');
      expect(network.capturedFields!['idusuariologged'], '42');
      expect(network.capturedFields!['actividadId'], '501');
      expect(network.capturedFields!['segmentoId'], '77');
      expect(network.capturedFields!['tipoFoto'], 'despues');
      expect(network.capturedFields!['description'], 'Después del trabajo');
      expect(network.capturedFiles, hasLength(1));
      expect(network.capturedFiles!.single.fieldName, 'file');
      expect(network.capturedFiles!.single.filePath, tmp.path);
      expect(network.capturedHeaders!['Authorization'], 'Bearer abc-token');
    });

    test('injected fileFactory is used to read file bytes', () async {
      final tmp = await _writeTmpImage('factory');
      addTearDown(() async {
        if (tmp.existsSync()) await tmp.delete();
      });

      var factoryCalls = 0;
      final network = _FakeNetworkService()
        ..response = NetworkResponse<dynamic>(
          statusCode: 200,
          data: <String, dynamic>{'id': 1, 'url': 'https://x/1.jpg'},
        );
      final adapter = ImagenRemoteAdapter(
        network,
        secureStorage: const _FakeSecureStorage(),
        fileFactory: (p) {
          factoryCalls++;
          return File(p);
        },
      );

      await adapter.push(
        entity: _makeImagen(localId: 'f', localPath: tmp.path),
        operation: SyncOperation.create,
      );

      expect(factoryCalls, 1);
    });
  });

  group('ImagenRemoteAdapter.push — unsupported operations', () {
    test('update returns SyncUnrecoverable', () async {
      final adapter = ImagenRemoteAdapter(
        _FakeNetworkService(),
        secureStorage: const _FakeSecureStorage(),
      );

      final outcome = await adapter.push(
        entity: _makeImagen(localId: 'u', localPath: '/tmp/nope.jpg'),
        operation: SyncOperation.update,
      );

      expect(outcome, isA<SyncUnrecoverable<ImagenSegmentoEntity>>());
      final unrec = outcome as SyncUnrecoverable<ImagenSegmentoEntity>;
      expect(unrec.reason, contains('update'));
    });

    test('delete returns SyncUnrecoverable', () async {
      final adapter = ImagenRemoteAdapter(
        _FakeNetworkService(),
        secureStorage: const _FakeSecureStorage(),
      );

      final outcome = await adapter.push(
        entity: _makeImagen(localId: 'd', localPath: '/tmp/nope.jpg'),
        operation: SyncOperation.delete,
      );

      expect(outcome, isA<SyncUnrecoverable<ImagenSegmentoEntity>>());
      final unrec = outcome as SyncUnrecoverable<ImagenSegmentoEntity>;
      expect(unrec.reason, contains('delete'));
    });
  });

  group('ImagenRemoteAdapter.push — transport errors', () {
    test('offline NetworkError maps to SyncRetryable', () async {
      final tmp = await _writeTmpImage('offline');
      addTearDown(() async {
        if (tmp.existsSync()) await tmp.delete();
      });

      final network = _FakeNetworkService()
        ..error = const NetworkError(
          category: NetworkErrorCategory.offline,
          message: 'No connection',
        );

      final adapter = ImagenRemoteAdapter(
        network,
        secureStorage: const _FakeSecureStorage(),
      );

      final outcome = await adapter.push(
        entity: _makeImagen(localId: 'off', localPath: tmp.path),
        operation: SyncOperation.create,
      );

      expect(outcome, isA<SyncRetryable<ImagenSegmentoEntity>>());
    });

    test('422 unrecoverable NetworkError maps to SyncUnrecoverable(422)',
        () async {
      final tmp = await _writeTmpImage('422');
      addTearDown(() async {
        if (tmp.existsSync()) await tmp.delete();
      });

      final network = _FakeNetworkService()
        ..error = const NetworkError(
          category: NetworkErrorCategory.unrecoverable,
          statusCode: 422,
          message: 'Unprocessable',
        );

      final adapter = ImagenRemoteAdapter(
        network,
        secureStorage: const _FakeSecureStorage(),
      );

      final outcome = await adapter.push(
        entity: _makeImagen(localId: '422', localPath: tmp.path),
        operation: SyncOperation.create,
      );

      expect(outcome, isA<SyncUnrecoverable<ImagenSegmentoEntity>>());
      final unrec = outcome as SyncUnrecoverable<ImagenSegmentoEntity>;
      expect(unrec.statusCode, 422);
    });
  });
}
