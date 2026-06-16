import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';

import 'package:helireport_desherbaje/core/result/data_result.dart';
import 'package:helireport_desherbaje/core/sync/sync.dart';
import 'package:helireport_desherbaje/data/model/mensaje_entity.dart';
import 'package:helireport_desherbaje/data/network/network_error.dart';
import 'package:helireport_desherbaje/data/network/network_response.dart';
import 'package:helireport_desherbaje/data/network/network_service.dart';
import 'package:helireport_desherbaje/data/repository/mensaje_segmento_repository.dart';
import 'package:helireport_desherbaje/data/sync/mensaje_local_store.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockNetworkService extends Mock implements NetworkService {}

class _MockMensajeLocalStore extends Mock implements MensajeLocalStore {}

class _MockOfflineRepository extends Mock
    implements OfflineRepository<MensajeSegmentoEntity> {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _segId = 42;

MensajeSegmentoEntity _makePending({
  String? clientId,
  String mensaje = 'hola',
  DateTime? createdAt,
  int segmentoId = _segId,
}) =>
    MensajeSegmentoEntity(
      clientId: clientId,
      segmentoId: segmentoId,
      mensaje: mensaje,
      createdAt: createdAt,
    );

NetworkResponse<dynamic> _okResponse(dynamic body) =>
    NetworkResponse<dynamic>(statusCode: 200, data: body);

const _offline = NetworkError(
  category: NetworkErrorCategory.offline,
  message: 'offline',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockNetworkService mockNetwork;
  late _MockMensajeLocalStore mockStore;
  late _MockOfflineRepository mockOffline;
  late MensajeSegmentoRepository repo;

  setUpAll(() {
    registerFallbackValue(_makePending());
  });

  setUp(() {
    Get.reset();
    mockNetwork = _MockNetworkService();
    mockStore = _MockMensajeLocalStore();
    mockOffline = _MockOfflineRepository();
    repo = MensajeSegmentoRepository(
      network: mockNetwork,
      offline: mockOffline,
      localStore: mockStore,
    );
  });

  tearDown(Get.reset);

  // ═══════════════════════════════════════════════════════════════════════════
  // NF-16 — caché ante CUALQUIER fallo de lectura
  // ═══════════════════════════════════════════════════════════════════════════

  group('NF-16 — cache fallback on any read failure', () {
    test('(NF-16a) generic Exception → DataSuccess with cache', () async {
      when(() => mockNetwork.get(any()))
          .thenThrow(Exception('unexpected'));
      final cached = [_makePending(mensaje: 'cached')];
      when(() => mockStore.findBySegmento(_segId))
          .thenAnswer((_) async => cached);

      final result = await repo.mensajesBySegmento(id: _segId);

      expect(result, isA<DataSuccess<List<MensajeSegmentoEntity>>>());
      expect((result as DataSuccess).data, cached);
    });

    test('(NF-16b) 200 with non-List body → DataSuccess with cache', () async {
      when(() => mockNetwork.get(any()))
          .thenAnswer((_) async => _okResponse({'error': 'bad'}));
      final cached = [_makePending(mensaje: 'cached')];
      when(() => mockStore.findBySegmento(_segId))
          .thenAnswer((_) async => cached);

      final result = await repo.mensajesBySegmento(id: _segId);

      expect(result, isA<DataSuccess<List<MensajeSegmentoEntity>>>());
      expect((result as DataSuccess).data, cached);
    });

    test('(NF-16c) fromJson throws on one item → cache success', () async {
      // A list with two items: one well-formed, one malformed (missing
      // segmento_id so the cast fails inside fromJson's readJsonDataUtil).
      final body = <dynamic>[
        {
          'id': 1,
          'client_id': 'abc',
          'segmento_id': 42,
          'mensaje': 'ok',
          'enviado_por': 1,
          'created_at': '2025-01-01T00:00:00.000Z',
          'updated_at': '2025-01-01T00:00:00.000Z',
        },
        // This will throw because the value is a wrong type for an int field
        // but to be deterministic we simulate the throw by putting a
        // non-parseable type that would cause fromJson to fail.
        'not-a-map',
      ];
      when(() => mockNetwork.get(any()))
          .thenAnswer((_) async => _okResponse(body));
      final cached = [_makePending(mensaje: 'cached')];
      when(() => mockStore.findBySegmento(_segId))
          .thenAnswer((_) async => cached);

      // The map-item parses correctly (1 entity), non-map skipped by
      // whereType<Map>. For a true fromJson throw test, wrap in a try:
      // The repository uses a per-element try-catch so one bad element
      // must not abort. We test the merge succeeds with the cache when
      // the body itself throws during the loop.

      // To actually trigger the per-element catch, we must make fromJson
      // throw. We do that by providing a map with bad type in 'segmento_id':
      final bodyWithBadItem = <dynamic>[
        {
          'id': null, // no remote id
          'client_id': 'abc',
          'segmento_id': 'NOT_AN_INT', // triggers cast exception in fromJson
          'mensaje': 'ok',
          'enviado_por': 1,
          'created_at': '2025-01-01T00:00:00.000Z',
          'updated_at': '2025-01-01T00:00:00.000Z',
        },
      ];
      when(() => mockNetwork.get(any()))
          .thenAnswer((_) async => _okResponse(bodyWithBadItem));
      when(() => mockStore.findBySegmento(_segId))
          .thenAnswer((_) async => cached);

      final result = await repo.mensajesBySegmento(id: _segId);

      // Either the bad item is skipped (merge with cache succeeds)
      // OR if readJsonDataUtil is lenient we get an empty remote merged with
      // cache. Either way it must be DataSuccess, not DataFailure.
      expect(result, isA<DataSuccess<List<MensajeSegmentoEntity>>>());
    });

    test(
        '(NF-16d) NetworkError(offline) AND store throws → DataFailure (irrecoverable)',
        () async {
      when(() => mockNetwork.get(any())).thenThrow(_offline);
      when(() => mockStore.findBySegmento(_segId))
          .thenThrow(Exception('DB locked'));

      final result = await repo.mensajesBySegmento(id: _segId);

      expect(result, isA<DataFailure<List<MensajeSegmentoEntity>>>());
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // NF-17 — empty cache → DataSuccess([])
  // ═══════════════════════════════════════════════════════════════════════════

  group('NF-17 — empty cache is a valid success', () {
    test('(NF-17a) offline + empty cache → DataSuccess([])', () async {
      when(() => mockNetwork.get(any())).thenThrow(_offline);
      when(() => mockStore.findBySegmento(_segId))
          .thenAnswer((_) async => []);

      final result = await repo.mensajesBySegmento(id: _segId);

      expect(result, isA<DataSuccess<List<MensajeSegmentoEntity>>>());
      expect((result as DataSuccess).data, isEmpty);
    });

    test('(NF-17b) online, remote and local both empty → DataSuccess([])',
        () async {
      when(() => mockNetwork.get(any()))
          .thenAnswer((_) async => _okResponse(<dynamic>[]));
      when(() => mockStore.findBySegmento(_segId))
          .thenAnswer((_) async => []);

      final result = await repo.mensajesBySegmento(id: _segId);

      expect(result, isA<DataSuccess<List<MensajeSegmentoEntity>>>());
      expect((result as DataSuccess).data, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // NF-18 — reliable dedup regardless of clientId re-minting
  // ═══════════════════════════════════════════════════════════════════════════

  group('NF-18 — cascading dedup key', () {
    test(
        '(NF-18a) same content in remote but different clientId than local pending → 1 copy',
        () async {
      final createdAt = DateTime(2025, 1, 1, 12, 0, 0).toUtc();
      final createdAtIso = createdAt.toIso8601String();

      // Remote has the message with a remote id (synced)
      when(() => mockNetwork.get(any())).thenAnswer((_) async => _okResponse([
            {
              'id': 99,
              'client_id': 'remote-client-id',
              'segmento_id': _segId,
              'mensaje': 'hola',
              'enviado_por': 1,
              'created_at': createdAtIso,
              'updated_at': createdAtIso,
            }
          ]));
      // Local pending has the same content but a different clientId
      // (e.g. clientId was re-minted after reinstall)
      final localPending = _makePending(
        clientId: 'totally-different-client-id',
        mensaje: 'hola',
        createdAt: createdAt,
      );
      when(() => mockStore.findBySegmento(_segId))
          .thenAnswer((_) async => [localPending]);

      final result = await repo.mensajesBySegmento(id: _segId);

      expect(result, isA<DataSuccess<List<MensajeSegmentoEntity>>>());
      // Must be deduplicated to 1 item (the remote one), not 2
      expect((result as DataSuccess).data.length, 1);
    });

    test(
        '(NF-18b) remote echoes id matching local pending id==null → dedup by r:<id>',
        () async {
      final createdAt = DateTime(2025, 6, 1, 10, 0, 0).toUtc();
      final createdAtIso = createdAt.toIso8601String();
      const ourClientId = 'our-client-id-xyz';

      // Remote echoes the same clientId and assigns an id
      when(() => mockNetwork.get(any())).thenAnswer((_) async => _okResponse([
            {
              'id': 77,
              'client_id': ourClientId,
              'segmento_id': _segId,
              'mensaje': 'mensaje',
              'enviado_por': 1,
              'created_at': createdAtIso,
              'updated_at': createdAtIso,
            }
          ]));
      // Local still has id==null (not yet marked synced)
      final localPending = _makePending(
        clientId: ourClientId,
        mensaje: 'mensaje',
        createdAt: createdAt,
      );
      when(() => mockStore.findBySegmento(_segId))
          .thenAnswer((_) async => [localPending]);

      final result = await repo.mensajesBySegmento(id: _segId);

      expect(result, isA<DataSuccess<List<MensajeSegmentoEntity>>>());
      // Fast-path dedup via clientId match → only 1 copy
      expect((result as DataSuccess).data.length, 1);
    });

    test(
        '(NF-18c) local pending NOT in remote → IS prepended (no false positive)',
        () async {
      // Remote has a different message
      when(() => mockNetwork.get(any())).thenAnswer((_) async => _okResponse([
            {
              'id': 55,
              'client_id': 'remote-abc',
              'segmento_id': _segId,
              'mensaje': 'mensaje remoto',
              'enviado_por': 1,
              'created_at': '2025-01-01T00:00:00.000Z',
              'updated_at': '2025-01-01T00:00:00.000Z',
            }
          ]));
      // Local pending is a different message — must not be deduplicated away
      final localPending = _makePending(
        clientId: 'local-pending-xyz',
        mensaje: 'mensaje local pendiente',
        createdAt: DateTime(2025, 6, 15, 9, 0, 0).toUtc(),
      );
      when(() => mockStore.findBySegmento(_segId))
          .thenAnswer((_) async => [localPending]);

      final result = await repo.mensajesBySegmento(id: _segId);

      expect(result, isA<DataSuccess<List<MensajeSegmentoEntity>>>());
      final items = (result as DataSuccess).data;
      // Both messages present: pending prepended + remote appended
      expect(items.length, 2);
      // Pending is first
      expect(items.first.id, isNull);
      expect(items.first.mensaje, 'mensaje local pendiente');
    });

    test('(NF-18d) backend echoes clientId → dedup via fast-path', () async {
      const ourClientId = 'echo-client-id';
      final createdAt = DateTime(2025, 3, 1, 8, 0, 0).toUtc();
      final createdAtIso = createdAt.toIso8601String();

      // Backend echoes our clientId with a remote id
      when(() => mockNetwork.get(any())).thenAnswer((_) async => _okResponse([
            {
              'id': 33,
              'client_id': ourClientId,
              'segmento_id': _segId,
              'mensaje': 'eco',
              'enviado_por': 2,
              'created_at': createdAtIso,
              'updated_at': createdAtIso,
            }
          ]));
      // Local still pending with same clientId
      final localPending = _makePending(
        clientId: ourClientId,
        mensaje: 'eco',
        createdAt: createdAt,
      );
      when(() => mockStore.findBySegmento(_segId))
          .thenAnswer((_) async => [localPending]);

      final result = await repo.mensajesBySegmento(id: _segId);

      expect(result, isA<DataSuccess<List<MensajeSegmentoEntity>>>());
      // Fast-path: clientId is in remoteClientIds → deduplicated to 1
      final successD = result as DataSuccess<List<MensajeSegmentoEntity>>;
      expect(successD.data.length, 1);
      // The remote entity (with id) wins
      expect(successD.data.first.id, 33);
    });
  });
}
