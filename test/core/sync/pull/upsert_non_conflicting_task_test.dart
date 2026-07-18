// Tests for UpsertNonConflictingTask — focus: resolved clientId is used for
// upsert and markSynced; one entitySynced action dispatched per item.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/core/sync/contracts/conflict_resolver.dart';
import 'package:helireport_desherbaje/core/sync/contracts/local_store.dart';
import 'package:helireport_desherbaje/core/sync/pull/pull_context.dart';
import 'package:helireport_desherbaje/core/sync/pull/tasks/upsert_non_conflicting_task.dart';
import 'package:helireport_desherbaje/core/sync/type_registry.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';
import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

// ─── Mocks ────────────────────────────────────────────────────────────────────

class MockLocalStore extends Mock implements LocalStore<SegmentoEntity> {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

TypeRegistration<SegmentoEntity> _registration(MockLocalStore store) =>
    TypeRegistration<SegmentoEntity>(
      entityType: 'segmento',
      store: store,
      conflictResolver: const ServerWinsResolver<SegmentoEntity>(),
      fromJson: SegmentoEntity.fromJson,
    );

SegmentoEntity _seg({
  required String clientId,
  int? id,
  DateTime? updatedAt,
}) {
  final ts = (updatedAt ?? DateTime(2025)).toIso8601String();
  return SegmentoEntity.fromJson({
    'client_id': clientId,
    'id': id,
    'ctname': 'CT1',
    'tipo_instalacion': 'lineal',
    'tipo_actividad': 'deshierbe_selectivo',
    'estado': 'propuesta',
    'descripcion': '',
    'updated_at': ts,
  });
}

void main() {
  late MockLocalStore mockStore;
  late UpsertNonConflictingTask<SegmentoEntity> task;

  setUpAll(() {
    sqfliteFfiInit();
    registerFallbackValue(SegmentoEntity.empty());
  });

  setUp(() {
    mockStore = MockLocalStore();
    task = UpsertNonConflictingTask<SegmentoEntity>();

    when(() => mockStore.upsert(any())).thenAnswer((_) async {});
    when(() => mockStore.markSynced(
          clientId: any(named: 'clientId'),
          remoteId: any(named: 'remoteId'),
        )).thenAnswer((_) async {});
  });

  PullContext<SegmentoEntity> buildCtx(List<ResolvedPullItem<SegmentoEntity>> items) {
    final ctx = PullContext<SegmentoEntity>(
      registration: _registration(mockStore),
    );
    ctx.safeToUpsert.addAll(items);
    return ctx;
  }

  Future<PullContext<SegmentoEntity>> runTask(
      PullContext<SegmentoEntity> ctx) async {
    final result = await task.execute(DataPipeline.of(ctx));
    return result.output;
  }

  group('UpsertNonConflictingTask', () {
    test(
      '(a) upsert is called with entity whose clientId matches the RESOLVED local clientId',
      () async {
        final local = _seg(clientId: 'local-cid', id: 42);
        final remote = _seg(clientId: 'fresh-uuid-from-backend', id: 42);

        // Resolved item: remote payload + local clientId
        final item = (remote: remote, clientId: 'local-cid', local: local);
        final ctx = await runTask(buildCtx([item]));

        // Capture argument passed to upsert
        final captured = verify(() => mockStore.upsert(captureAny())).captured;
        expect(captured, hasLength(1));
        final upserted = captured.first as SegmentoEntity;

        // The entity stored must carry the LOCAL clientId, not the backend's fresh UUID
        expect(upserted.clientId, equals('local-cid'),
            reason: 'upsert must use the resolved local clientId');
        // Remote payload (id) must be preserved
        expect(upserted.id, equals(42),
            reason: 'remote payload is preserved via fromJson round-trip');
        expect(ctx.upserted, equals(1));
      },
    );

    test(
      '(b) markSynced is called with the resolved clientId and the remote remoteId',
      () async {
        final remote = _seg(clientId: 'fresh-uuid', id: 7);
        final item = (remote: remote, clientId: 'stable-local-cid', local: null);

        await runTask(buildCtx([item]));

        verify(() => mockStore.markSynced(
              clientId: 'stable-local-cid',
              remoteId: '7',
            )).called(1);
      },
    );

    test(
      '(c) one upsert + one markSynced per item — multiple items are all processed',
      () async {
        final items = [
          (
            remote: _seg(clientId: 'uuid-a', id: 1),
            clientId: 'local-a',
            local: null as SegmentoEntity?,
          ),
          (
            remote: _seg(clientId: 'uuid-b', id: 2),
            clientId: 'local-b',
            local: null as SegmentoEntity?,
          ),
          (
            remote: _seg(clientId: 'uuid-c', id: 3),
            clientId: 'local-c',
            local: null as SegmentoEntity?,
          ),
        ];

        final ctx = await runTask(buildCtx(items));

        verify(() => mockStore.upsert(any())).called(3);
        verify(() => mockStore.markSynced(
              clientId: any(named: 'clientId'),
              remoteId: any(named: 'remoteId'),
            )).called(3);
        expect(ctx.upserted, equals(3));
      },
    );

    test(
      '(d) new item (no local) — upsert called with the remote clientId as-is',
      () async {
        final remote = _seg(clientId: 'totally-new-uuid', id: 99);
        // No local found: clientId == remote.clientId
        final item = (remote: remote, clientId: 'totally-new-uuid', local: null);

        await runTask(buildCtx([item]));

        final captured = verify(() => mockStore.upsert(captureAny())).captured;
        final upserted = captured.first as SegmentoEntity;
        expect(upserted.clientId, equals('totally-new-uuid'));
        expect(upserted.id, equals(99));
      },
    );

    test(
      '(e) empty safeToUpsert list — no store calls, upserted counter stays 0',
      () async {
        final ctx = await runTask(buildCtx([]));

        verifyNever(() => mockStore.upsert(any()));
        verifyNever(() => mockStore.markSynced(
              clientId: any(named: 'clientId'),
              remoteId: any(named: 'remoteId'),
            ));
        expect(ctx.upserted, equals(0));
      },
    );
  });
}
