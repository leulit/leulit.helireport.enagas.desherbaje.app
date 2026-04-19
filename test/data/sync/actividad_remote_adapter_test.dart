import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helireport_desherbaje/core/sync/contracts/remote_adapter.dart';
import 'package:helireport_desherbaje/core/sync/contracts/sync_job.dart';
import 'package:helireport_desherbaje/data/network/network_error.dart';
import 'package:helireport_desherbaje/data/network/network_response.dart';
import 'package:helireport_desherbaje/data/network/network_service.dart';
import 'package:helireport_desherbaje/data/sync/actividad_remote_adapter.dart';
import 'package:helireport_desherbaje/domain/entities/actividad_entity.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';

class PostCall {
  final String path;
  final Object? body;
  final Map<String, dynamic>? queryParameters;
  final Map<String, String>? headers;
  const PostCall({
    required this.path,
    required this.body,
    required this.queryParameters,
    required this.headers,
  });
}

/// Records invocations and returns programmable results.
class FakeNetworkService extends NetworkService {
  final List<PostCall> calls = <PostCall>[];

  NetworkResponse<dynamic>? responseToReturn;
  NetworkError? errorToThrow;

  @override
  Future<NetworkResponse<dynamic>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    calls.add(PostCall(
      path: path,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
    ));
    final err = errorToThrow;
    if (err != null) throw err;
    final resp = responseToReturn;
    if (resp != null) return resp;
    throw StateError('FakeNetworkService.post: no result programmed');
  }
}

/// Subclass so tests never hit the platform channel.
class FakeSecureStorage extends FlutterSecureStorage {
  final String? stored;
  const FakeSecureStorage({this.stored});

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      stored;
}

ActividadEntity _makeActividad({
  int id = 7,
  EstadoActividad estado = EstadoActividad.ejecucion,
}) {
  return ActividadEntity(
    id: id,
    posicionId: 1,
    estado: estado,
    descripcion: 'desc',
    superficieM2: 1,
    costeEstimado: 2,
    fechaProgramada: DateTime(2026, 4, 19),
    fechaInicio: DateTime(2026, 4, 19),
    fechaFin: DateTime(2026, 4, 19),
    segmentos: const <SegmentoEntity>[],
  );
}

void main() {
  late FakeNetworkService network;
  late ActividadRemoteAdapter adapter;

  setUp(() {
    network = FakeNetworkService();
    adapter = ActividadRemoteAdapter(
      network,
      storage: const FakeSecureStorage(stored: 'token-abc'),
    );
  });

  group('ActividadRemoteAdapter.push(update)', () {
    test('returns SyncSuccess with remoteId on 2xx', () async {
      network.responseToReturn = const NetworkResponse<dynamic>(
        statusCode: 200,
        data: {'success': true},
      );

      final outcome = await adapter.push(
        entity: _makeActividad(id: 42),
        operation: SyncOperation.update,
      );

      expect(outcome, isA<SyncSuccess<ActividadEntity>>());
      expect((outcome as SyncSuccess<ActividadEntity>).remoteId, '42');
      expect(network.calls, hasLength(1));
      expect(network.calls.single.path, '/actividades/update/42');
      expect(network.calls.single.body, {'estado': 'Ejecución'});
      expect(
        network.calls.single.headers,
        {'Authorization': 'Bearer token-abc'},
      );
    });

    test('omits auth header when token is absent', () async {
      adapter = ActividadRemoteAdapter(
        network,
        storage: const FakeSecureStorage(),
      );
      network.responseToReturn = const NetworkResponse<dynamic>(
        statusCode: 200,
        data: {'success': true},
      );

      await adapter.push(
        entity: _makeActividad(id: 1),
        operation: SyncOperation.update,
      );

      expect(network.calls.single.headers, isNull);
    });

    test('non-2xx without NetworkError maps to SyncUnrecoverable', () async {
      network.responseToReturn = const NetworkResponse<dynamic>(
        statusCode: 418,
        data: null,
      );

      final outcome = await adapter.push(
        entity: _makeActividad(),
        operation: SyncOperation.update,
      );

      expect(outcome, isA<SyncUnrecoverable<ActividadEntity>>());
      final u = outcome as SyncUnrecoverable<ActividadEntity>;
      expect(u.statusCode, 418);
      expect(u.reason, contains('418'));
    });
  });

  group('ActividadRemoteAdapter.push rejects unsupported operations', () {
    test('create → SyncUnrecoverable, no network call', () async {
      final outcome = await adapter.push(
        entity: _makeActividad(),
        operation: SyncOperation.create,
      );
      expect(outcome, isA<SyncUnrecoverable<ActividadEntity>>());
      expect(
        (outcome as SyncUnrecoverable<ActividadEntity>).reason,
        contains('create'),
      );
      expect(network.calls, isEmpty);
    });

    test('delete → SyncUnrecoverable, no network call', () async {
      final outcome = await adapter.push(
        entity: _makeActividad(),
        operation: SyncOperation.delete,
      );
      expect(outcome, isA<SyncUnrecoverable<ActividadEntity>>());
      expect(
        (outcome as SyncUnrecoverable<ActividadEntity>).reason,
        contains('delete'),
      );
      expect(network.calls, isEmpty);
    });
  });

  group('ActividadRemoteAdapter error mapping', () {
    test('offline → SyncRetryable', () async {
      network.errorToThrow = const NetworkError(
        category: NetworkErrorCategory.offline,
        message: 'no network',
      );

      final outcome = await adapter.push(
        entity: _makeActividad(),
        operation: SyncOperation.update,
      );

      expect(outcome, isA<SyncRetryable<ActividadEntity>>());
    });

    test('unauthorized 401 → SyncUnrecoverable with statusCode', () async {
      network.errorToThrow = const NetworkError(
        category: NetworkErrorCategory.unauthorized,
        statusCode: 401,
        message: 'unauthorized',
      );

      final outcome = await adapter.push(
        entity: _makeActividad(),
        operation: SyncOperation.update,
      );

      expect(outcome, isA<SyncUnrecoverable<ActividadEntity>>());
      expect(
        (outcome as SyncUnrecoverable<ActividadEntity>).statusCode,
        401,
      );
    });

    test('conflict 409 → SyncUnrecoverable (documented current behaviour)',
        () async {
      network.errorToThrow = const NetworkError(
        category: NetworkErrorCategory.conflict,
        statusCode: 409,
        message: 'version mismatch',
      );

      final outcome = await adapter.push(
        entity: _makeActividad(),
        operation: SyncOperation.update,
      );

      expect(outcome, isA<SyncUnrecoverable<ActividadEntity>>());
      final u = outcome as SyncUnrecoverable<ActividadEntity>;
      expect(u.statusCode, 409);
      expect(u.reason, contains('Conflict'));
    });
  });
}
