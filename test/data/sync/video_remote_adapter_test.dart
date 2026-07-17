// Tests for VideoRemoteAdapter — new TUS-like chunked upload protocol.
//
// Covers:
//   - mimeForExtension: .mp4, .mov, fallback
//   - push(create): init → chunk(s) → complete → SyncSuccess with uploadId
//   - push(create): uploadId persisted to store after init
//   - push(create): resume — uploadId present → GET status → continue from offset
//   - push(create): re-init on 404 status (session expired)
//   - push(create): already complete on resume → idempotent SyncSuccess
//   - push(create): chunk retry on transient error (retryable → success on 2nd attempt)
//   - push(create): 401 → SyncUnrecoverable, NOT AuthExpiredException
//   - push(create): offline/timeout/5xx → SyncRetryable
//   - push(create): 4xx unrecoverable → SyncUnrecoverable
//   - push(update/delete): → SyncUnrecoverable
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/core/sync/contracts/remote_adapter.dart';
import 'package:helireport_desherbaje/core/sync/contracts/sync_job.dart'
    show SyncOperation;
import 'package:helireport_desherbaje/data/network/network_error.dart';
import 'package:helireport_desherbaje/data/network/network_response.dart';
import 'package:helireport_desherbaje/data/network/network_service.dart';
import 'package:helireport_desherbaje/data/sync/video_local_store.dart';
import 'package:helireport_desherbaje/data/sync/video_remote_adapter.dart';
import 'package:helireport_desherbaje/domain/entities/video_segmento_entity.dart';

// ─── Fake NetworkService ──────────────────────────────────────────────────────
//
// Subclasses NetworkService (skipping Dio init) and overrides the 4 video
// methods with queued response stubs.  Queues process front-to-back so each
// test can describe the exact sequence of server responses.

class _FakeNetworkService extends NetworkService {
  @override
  // ignore: must_call_super
  void onInit() {} // Skip Dio init

  final List<dynamic> _initQ = [];
  final List<dynamic> _patchQ = [];
  final List<dynamic> _statusQ = [];
  final List<dynamic> _completeQ = [];

  // Captured args for assertion
  List<Map<String, dynamic>> capturedInitBodies = [];
  List<({String uploadId, int offset, Uint8List bytes})> capturedChunks = [];
  List<String> capturedStatusIds = [];
  List<String> capturedCompleteIds = [];

  void queueInit(NetworkResponse<dynamic> r) => _initQ.add(r);
  void queueInitError(NetworkError e) => _initQ.add(e);
  void queuePatch(NetworkResponse<dynamic> r) => _patchQ.add(r);
  void queuePatchError(NetworkError e) => _patchQ.add(e);
  void queueStatus(NetworkResponse<dynamic> r) => _statusQ.add(r);
  void queueStatusError(NetworkError e) => _statusQ.add(e);
  void queueComplete(NetworkResponse<dynamic> r) => _completeQ.add(r);

  dynamic _dequeue(List<dynamic> q, String name) {
    if (q.isEmpty) throw StateError('$name queue is empty');
    return q.removeAt(0);
  }

  @override
  Future<NetworkResponse<dynamic>> initVideoUpload(
    Map<String, dynamic> body,
  ) async {
    capturedInitBodies.add(body);
    final item = _dequeue(_initQ, 'init');
    if (item is NetworkError) throw item;
    return item as NetworkResponse<dynamic>;
  }

  @override
  Future<NetworkResponse<dynamic>> postVideoChunk({
    required String uploadId,
    required int uploadOffset,
    required Uint8List bytes,
  }) async {
    capturedChunks.add((uploadId: uploadId, offset: uploadOffset, bytes: bytes));
    final item = _dequeue(_patchQ, 'patch');
    if (item is NetworkError) throw item;
    return item as NetworkResponse<dynamic>;
  }

  @override
  Future<NetworkResponse<dynamic>> getVideoStatus(String uploadId) async {
    capturedStatusIds.add(uploadId);
    final item = _dequeue(_statusQ, 'status');
    if (item is NetworkError) throw item;
    return item as NetworkResponse<dynamic>;
  }

  @override
  Future<NetworkResponse<dynamic>> completeVideoUpload(String uploadId) async {
    capturedCompleteIds.add(uploadId);
    final item = _dequeue(_completeQ, 'complete');
    if (item is NetworkError) throw item;
    return item as NetworkResponse<dynamic>;
  }
}

// ─── Mock VideoLocalStore ─────────────────────────────────────────────────────

class _MockVideoLocalStore extends Mock implements VideoLocalStore {}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Future<File> _tmpFile({int bytes = 10}) async {
  final f = File(
    '${Directory.systemTemp.path}'
    '/vid_test_${DateTime.now().microsecondsSinceEpoch}.mp4',
  );
  await f.writeAsBytes(List.filled(bytes, 0x42));
  return f;
}

VideoSegmentoEntity _entity({
  String clientId = 'test-cid',
  String filename = 'video.mp4',
  int segmentoId = 5,
  int actividadId = 1,
  int uploadOffset = 0,
  String? uploadId,
  required String ruta,
}) {
  final e = VideoSegmentoEntity(
    clientId: clientId,
    actividadId: actividadId,
    segmentoId: segmentoId,
    tipoVideo: TipoVideo.antes,
    filename: filename,
    ruta: ruta,
    capturadaAt: DateTime.utc(2026, 1, 1),
  )
    ..uploadOffset = uploadOffset
    ..uploadId = uploadId;
  return e;
}

NetworkResponse<dynamic> _okInit({String uploadId = 'up-uuid'}) =>
    NetworkResponse<dynamic>(
      statusCode: 201,
      data: {'uploadId': uploadId, 'offset': 0, 'segmentoId': 5},
    );

NetworkResponse<dynamic> _okPatch({required int offset}) =>
    NetworkResponse<dynamic>(statusCode: 200, data: {'offset': offset});

NetworkResponse<dynamic> _okComplete({String uploadId = 'up-uuid'}) =>
    NetworkResponse<dynamic>(
      statusCode: 200,
      data: {'uploadId': uploadId, 'status': 'recibido'},
    );

NetworkResponse<dynamic> _okStatus({
  String uploadId = 'up-uuid',
  int offset = 0,
  bool complete = false,
}) =>
    NetworkResponse<dynamic>(
      statusCode: 200,
      data: {
        'uploadId': uploadId,
        'offset': offset,
        'complete': complete,
      },
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late _FakeNetworkService network;
  late _MockVideoLocalStore store;
  late VideoRemoteAdapter adapter;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    registerFallbackValue('');
    registerFallbackValue(0);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    network = _FakeNetworkService();
    store = _MockVideoLocalStore();
    when(() => store.saveUploadId(any(), any())).thenAnswer((_) async {});
    when(() => store.saveUploadOffset(any(), any())).thenAnswer((_) async {});
    adapter = VideoRemoteAdapter(network, store);
  });

  // ─── mimeForExtension ────────────────────────────────────────────────────

  group('mimeForExtension', () {
    test('.mp4 → video/mp4', () {
      expect(adapter.mimeForExtension('clip.mp4'), equals('video/mp4'));
    });

    test('.mov → video/quicktime', () {
      expect(adapter.mimeForExtension('clip.mov'), equals('video/quicktime'));
    });

    test('.webm → video/webm', () {
      expect(adapter.mimeForExtension('clip.webm'), equals('video/webm'));
    });

    test('unknown extension → video/mp4 (fallback)', () {
      expect(adapter.mimeForExtension('clip.xyz'), equals('video/mp4'));
    });

    test('uppercase extension → case-insensitive', () {
      expect(adapter.mimeForExtension('CLIP.MP4'), equals('video/mp4'));
    });
  });

  // ─── push(create) — happy path: init → chunk → complete ─────────────────

  group('push(create) — happy path', () {
    late File f;
    setUp(() async => f = await _tmpFile(bytes: 10));
    tearDown(() async { if (f.existsSync()) await f.delete(); });

    test('init body contains required fields', () async {
      network
        ..queueInit(_okInit())
        ..queuePatch(_okPatch(offset: 10))
        ..queueComplete(_okComplete());

      final entity = _entity(ruta: f.path, filename: 'clip.mp4');
      await adapter.push(entity: entity, operation: SyncOperation.create);

      final body = network.capturedInitBodies.first;
      expect(body['originalFilename'], equals('clip.mp4'));
      expect(body['mimeType'], equals('video/mp4'));
      expect(body['clientId'], equals('test-cid'));
      expect(body['segmentoId'], equals(5));
      expect(body['totalBytes'], equals(10));
    });

    test('returns SyncSuccess with remoteId = uploadId', () async {
      network
        ..queueInit(_okInit(uploadId: 'abc-123'))
        ..queuePatch(_okPatch(offset: 10))
        ..queueComplete(_okComplete(uploadId: 'abc-123'));

      final entity = _entity(ruta: f.path);
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(outcome, isA<SyncSuccess<VideoSegmentoEntity>>());
      final success = outcome as SyncSuccess<VideoSegmentoEntity>;
      expect(success.remoteId, equals('abc-123'));
    });

    test('serverVersion.url is the deterministic download URL', () async {
      network
        ..queueInit(_okInit(uploadId: 'xyz'))
        ..queuePatch(_okPatch(offset: 10))
        ..queueComplete(_okComplete(uploadId: 'xyz'));

      final entity = _entity(ruta: f.path);
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.create);

      final success = outcome as SyncSuccess<VideoSegmentoEntity>;
      expect(
        success.serverVersion?.url,
        contains('/api/enagas/v1/videos/download/xyz'),
      );
    });

    test('serverVersion.subidaAt is set to now', () async {
      network
        ..queueInit(_okInit())
        ..queuePatch(_okPatch(offset: 10))
        ..queueComplete(_okComplete());

      final before = DateTime.now().subtract(const Duration(seconds: 2));
      final entity = _entity(ruta: f.path);
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.create);

      final success = outcome as SyncSuccess<VideoSegmentoEntity>;
      expect(success.serverVersion?.subidaAt, isNotNull);
      expect(
        success.serverVersion!.subidaAt!.isAfter(before),
        isTrue,
      );
    });

    test('saveUploadId is called on store after init', () async {
      network
        ..queueInit(_okInit(uploadId: 'up-42'))
        ..queuePatch(_okPatch(offset: 10))
        ..queueComplete(_okComplete(uploadId: 'up-42'));

      final entity = _entity(ruta: f.path);
      await adapter.push(entity: entity, operation: SyncOperation.create);

      verify(() => store.saveUploadId('test-cid', 'up-42')).called(1);
    });

    test('saveUploadOffset called on store after each chunk', () async {
      network
        ..queueInit(_okInit())
        ..queuePatch(_okPatch(offset: 10))
        ..queueComplete(_okComplete());

      final entity = _entity(ruta: f.path);
      await adapter.push(entity: entity, operation: SyncOperation.create);

      verify(() => store.saveUploadOffset(any(), any()))
          .called(greaterThan(0));
    });

    test('chunk PATCH is called with Upload-Offset = 0 on first chunk', () async {
      network
        ..queueInit(_okInit())
        ..queuePatch(_okPatch(offset: 10))
        ..queueComplete(_okComplete());

      final entity = _entity(ruta: f.path);
      await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(network.capturedChunks.first.offset, equals(0));
    });

    test('complete is called after all chunks', () async {
      network
        ..queueInit(_okInit(uploadId: 'done-id'))
        ..queuePatch(_okPatch(offset: 10))
        ..queueComplete(_okComplete(uploadId: 'done-id'));

      final entity = _entity(ruta: f.path);
      await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(network.capturedCompleteIds, contains('done-id'));
    });
  });

  // ─── push(create) — resume: uploadId present ────────────────────────────

  group('push(create) — resume', () {
    late File f;
    setUp(() async => f = await _tmpFile(bytes: 10));
    tearDown(() async { if (f.existsSync()) await f.delete(); });

    test('GET status is called instead of init when uploadId is set', () async {
      network
        ..queueStatus(_okStatus(uploadId: 'resume-id', offset: 0))
        ..queuePatch(_okPatch(offset: 10))
        ..queueComplete(_okComplete(uploadId: 'resume-id'));

      final entity = _entity(ruta: f.path, uploadId: 'resume-id');
      await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(network.capturedInitBodies, isEmpty);
      expect(network.capturedStatusIds, contains('resume-id'));
    });

    test('init is NOT called when resuming', () async {
      network
        ..queueStatus(_okStatus(uploadId: 'r-id', offset: 5))
        ..queuePatch(_okPatch(offset: 10))
        ..queueComplete(_okComplete(uploadId: 'r-id'));

      final entity = _entity(ruta: f.path, uploadId: 'r-id');
      await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(network.capturedInitBodies, isEmpty);
    });

    test('chunk starts from offset returned by GET status', () async {
      network
        ..queueStatus(_okStatus(uploadId: 'r-id', offset: 5))
        ..queuePatch(_okPatch(offset: 10))
        ..queueComplete(_okComplete(uploadId: 'r-id'));

      final entity = _entity(ruta: f.path, uploadId: 'r-id');
      await adapter.push(entity: entity, operation: SyncOperation.create);

      // First (and only) chunk must start from offset 5.
      expect(network.capturedChunks.first.offset, equals(5));
    });

    test('already complete → SyncSuccess without sending any chunk', () async {
      network.queueStatus(
        _okStatus(uploadId: 'done-id', offset: 10, complete: true),
      );

      final entity = _entity(ruta: f.path, uploadId: 'done-id');
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(outcome, isA<SyncSuccess<VideoSegmentoEntity>>());
      expect(network.capturedChunks, isEmpty);
      expect(network.capturedCompleteIds, isEmpty);
    });
  });

  // ─── push(create) — re-init on 404 status ───────────────────────────────

  group('push(create) — re-init on 404 status', () {
    late File f;
    setUp(() async => f = await _tmpFile(bytes: 10));
    tearDown(() async { if (f.existsSync()) await f.delete(); });

    test('404 on GET status triggers re-init', () async {
      network
        ..queueStatusError(const NetworkError(
          category: NetworkErrorCategory.unrecoverable,
          statusCode: 404,
          message: 'Not found',
        ))
        ..queueInit(_okInit(uploadId: 'new-id'))
        ..queuePatch(_okPatch(offset: 10))
        ..queueComplete(_okComplete(uploadId: 'new-id'));

      final entity = _entity(ruta: f.path, uploadId: 'old-id');
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(outcome, isA<SyncSuccess<VideoSegmentoEntity>>());
      expect(network.capturedInitBodies, isNotEmpty);
      final success = outcome as SyncSuccess<VideoSegmentoEntity>;
      expect(success.remoteId, equals('new-id'));
    });

    test('saveUploadId called with new uploadId after re-init', () async {
      network
        ..queueStatusError(const NetworkError(
          category: NetworkErrorCategory.unrecoverable,
          statusCode: 404,
          message: 'Not found',
        ))
        ..queueInit(_okInit(uploadId: 'fresh-id'))
        ..queuePatch(_okPatch(offset: 10))
        ..queueComplete(_okComplete(uploadId: 'fresh-id'));

      final entity = _entity(ruta: f.path, uploadId: 'stale-id');
      await adapter.push(entity: entity, operation: SyncOperation.create);

      verify(() => store.saveUploadId('test-cid', 'fresh-id')).called(1);
    });
  });

  // ─── push(create) — chunk retry on transient errors ─────────────────────

  group('push(create) — chunk retry', () {
    late File f;
    setUp(() async => f = await _tmpFile(bytes: 10));
    tearDown(() async { if (f.existsSync()) await f.delete(); });

    test('timeout on chunk → retried → success', () async {
      network
        ..queueInit(_okInit(uploadId: 'retry-id'))
        ..queuePatchError(const NetworkError(
          category: NetworkErrorCategory.timeout,
          message: 'Timeout',
        ))
        // Before 2nd attempt, status check is issued.
        ..queueStatus(_okStatus(uploadId: 'retry-id', offset: 0))
        ..queuePatch(_okPatch(offset: 10))
        ..queueComplete(_okComplete(uploadId: 'retry-id'));

      final entity = _entity(ruta: f.path, uploadId: null);
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(outcome, isA<SyncSuccess<VideoSegmentoEntity>>());
      // Two PATCH attempts (1 fail + 1 success).
      expect(network.capturedChunks.length, equals(2));
    });

    test('5xx on chunk → retried → success', () async {
      network
        ..queueInit(_okInit())
        ..queuePatchError(const NetworkError(
          category: NetworkErrorCategory.retryable,
          statusCode: 503,
          message: 'Service unavailable',
        ))
        ..queueStatus(_okStatus())
        ..queuePatch(_okPatch(offset: 10))
        ..queueComplete(_okComplete());

      final entity = _entity(ruta: f.path);
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(outcome, isA<SyncSuccess<VideoSegmentoEntity>>());
    });

    test('unrecoverable 4xx on chunk → NOT retried → SyncUnrecoverable', () async {
      network
        ..queueInit(_okInit())
        ..queuePatchError(const NetworkError(
          category: NetworkErrorCategory.unrecoverable,
          statusCode: 400,
          message: 'Bad request',
        ));

      final entity = _entity(ruta: f.path);
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(outcome, isA<SyncUnrecoverable<VideoSegmentoEntity>>());
      // Only 1 PATCH attempt — unrecoverable is not retried.
      expect(network.capturedChunks.length, equals(1));
    });
  });

  // ─── push(create) — error mapping ───────────────────────────────────────

  group('push(create) — error mapping', () {
    late File f;
    setUp(() async => f = await _tmpFile(bytes: 10));
    tearDown(() async { if (f.existsSync()) await f.delete(); });

    test('offline on init → SyncRetryable', () async {
      network.queueInitError(const NetworkError(
        category: NetworkErrorCategory.offline,
        message: 'No network',
      ));

      final entity = _entity(ruta: f.path);
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(outcome, isA<SyncRetryable<VideoSegmentoEntity>>());
    });

    test('timeout on init → SyncRetryable', () async {
      network.queueInitError(const NetworkError(
        category: NetworkErrorCategory.timeout,
        message: 'Timeout',
      ));

      final entity = _entity(ruta: f.path);
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(outcome, isA<SyncRetryable<VideoSegmentoEntity>>());
    });

    test('5xx on init → SyncRetryable', () async {
      network.queueInitError(const NetworkError(
        category: NetworkErrorCategory.retryable,
        statusCode: 503,
        message: 'Service unavailable',
      ));

      final entity = _entity(ruta: f.path);
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(outcome, isA<SyncRetryable<VideoSegmentoEntity>>());
    });

    test('400 on init → SyncUnrecoverable', () async {
      network.queueInitError(const NetworkError(
        category: NetworkErrorCategory.unrecoverable,
        statusCode: 400,
        message: 'Bad request',
      ));

      final entity = _entity(ruta: f.path);
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(outcome, isA<SyncUnrecoverable<VideoSegmentoEntity>>());
    });

    test(
        '401 → SyncUnrecoverable with HMAC reason, NOT AuthExpiredException',
        () async {
      network.queueInitError(const NetworkError(
        category: NetworkErrorCategory.unauthorized,
        statusCode: 401,
        message: 'Unauthorized',
      ));

      final entity = _entity(ruta: f.path);
      // Must NOT throw AuthExpiredException — video uses HMAC, not Bearer.
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(outcome, isA<SyncUnrecoverable<VideoSegmentoEntity>>());
      final unrecoverable = outcome as SyncUnrecoverable<VideoSegmentoEntity>;
      expect(unrecoverable.statusCode, equals(401));
      // Verify the reason explains HMAC, not session expiry.
      expect(unrecoverable.reason.toLowerCase(), contains('hmac'));
    });

    test('401 resolves normally (does NOT throw AuthExpiredException)', () async {
      network.queueInitError(const NetworkError(
        category: NetworkErrorCategory.unauthorized,
        statusCode: 401,
        message: 'Unauthorized',
      ));

      final entity = _entity(ruta: f.path);
      // expectLater with completion verifies no exception was thrown.
      await expectLater(
        adapter.push(entity: entity, operation: SyncOperation.create),
        completion(isA<SyncUnrecoverable<VideoSegmentoEntity>>()),
      );
    });

    test('403 → SyncUnrecoverable with HMAC reason', () async {
      network.queueInitError(const NetworkError(
        category: NetworkErrorCategory.unauthorized,
        statusCode: 403,
        message: 'Forbidden',
      ));

      final entity = _entity(ruta: f.path);
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.create);

      expect(outcome, isA<SyncUnrecoverable<VideoSegmentoEntity>>());
      final unrecoverable = outcome as SyncUnrecoverable<VideoSegmentoEntity>;
      expect(unrecoverable.reason.toLowerCase(), contains('hmac'));
    });
  });

  // ─── push — unsupported operations ──────────────────────────────────────

  group('push — unsupported operations', () {
    test('SyncOperation.update → SyncUnrecoverable', () async {
      final entity = _entity(ruta: '/tmp/dummy.mp4');
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.update);
      expect(outcome, isA<SyncUnrecoverable<VideoSegmentoEntity>>());
    });

    test('SyncOperation.delete → SyncUnrecoverable', () async {
      final entity = _entity(ruta: '/tmp/dummy.mp4');
      final outcome =
          await adapter.push(entity: entity, operation: SyncOperation.delete);
      expect(outcome, isA<SyncUnrecoverable<VideoSegmentoEntity>>());
    });
  });
}
