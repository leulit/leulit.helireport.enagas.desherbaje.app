// Tests for DetectConflictsTask — focus: identity resolution by remoteId,
// conflict classification, NF-4 (syncing jobs), ResolvedPullItem shape.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/core/sync/contracts/conflict_resolver.dart';
import 'package:helireport_desherbaje/core/sync/contracts/local_store.dart';
import 'package:helireport_desherbaje/core/sync/contracts/sync_job.dart';
import 'package:helireport_desherbaje/core/sync/contracts/syncable.dart';
import 'package:helireport_desherbaje/core/sync/outbox/outbox_queue.dart';
import 'package:helireport_desherbaje/core/sync/pull/pull_context.dart';
import 'package:helireport_desherbaje/core/sync/pull/tasks/detect_conflicts_task.dart';
import 'package:helireport_desherbaje/core/sync/type_registry.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';
import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

// ─── Mocks ────────────────────────────────────────────────────────────────────

class MockLocalStore extends Mock implements LocalStore<SegmentoEntity> {}

class MockOutboxQueue extends Mock implements OutboxQueue {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Fake TypeRegistration with a mock store.
TypeRegistration<SegmentoEntity> _registration(
  MockLocalStore store,
) =>
    TypeRegistration<SegmentoEntity>(
      entityType: 'segmento',
      store: store,
      conflictResolver: const ServerWinsResolver<SegmentoEntity>(),
      fromJson: SegmentoEntity.fromJson,
    );

/// Minimal segmento helper.
SegmentoEntity _seg({
  required String clientId,
  int? id,
  DateTime? updatedAt,
  EstadoActividad estado = EstadoActividad.propuesta,
}) {
  final ts = (updatedAt ?? DateTime(2025)).toIso8601String();
  return SegmentoEntity.fromJson({
    'client_id': clientId,
    'id': id,
    'ct_id': 1,
    'tipo_instalacion': 'lineal',
    'tipo_actividad': 'deshierbe_selectivo',
    'estado': 'propuesta',
    'descripcion': '',
    'updated_at': ts,
  });
}

/// A fake SyncJob for use in mocks.
SyncJob _fakeJob({
  required String clientId,
  required SyncStatus status,
  SyncOperation operation = SyncOperation.update,
}) =>
    SyncJob(
      id: 1,
      entityType: 'segmento',
      clientId: clientId,
      operation: operation,
      status: status,
      attempts: 0,
      createdAt: DateTime(2025),
    );

void main() {
  late MockLocalStore mockStore;
  late MockOutboxQueue mockQueue;
  late DetectConflictsTask<SegmentoEntity> task;

  setUpAll(() {
    sqfliteFfiInit();
    registerFallbackValue(SegmentoEntity.empty());
    registerFallbackValue(SyncStatus.pending);
  });

  setUp(() {
    mockStore = MockLocalStore();
    mockQueue = MockOutboxQueue();
    task = DetectConflictsTask<SegmentoEntity>(outbox: mockQueue);

    // Default: no pending/rejected/syncing jobs.
    when(() => mockQueue.pendingJobs(entityType: any(named: 'entityType')))
        .thenAnswer((_) async => []);
    when(() => mockQueue.rejectedJobs(entityType: any(named: 'entityType')))
        .thenAnswer((_) async => []);
    when(() => mockQueue.syncingJobs(entityType: any(named: 'entityType')))
        .thenAnswer((_) async => []);
  });

  PullContext<SegmentoEntity> _ctx(List<SegmentoEntity> remoteItems) {
    final ctx = PullContext<SegmentoEntity>(
      registration: _registration(mockStore),
    );
    ctx.remoteItems = remoteItems;
    return ctx;
  }

  Future<PullContext<SegmentoEntity>> _run(
      PullContext<SegmentoEntity> ctx) async {
    final result =
        await task.execute(DataPipeline.of(ctx));
    return result.output;
  }

  // ─── Tests ─────────────────────────────────────────────────────────────────

  group('DetectConflictsTask', () {
    test(
      '(a) match by remoteId, different clientId, remote newer, no pending → '
      'safeToUpsert with LOCAL clientId',
      () async {
        final localUpdatedAt = DateTime(2025, 1, 1);
        final remoteUpdatedAt = DateTime(2025, 6, 1); // newer

        final local = _seg(
          clientId: 'local-cid',
          id: 42,
          updatedAt: localUpdatedAt,
        );
        final remote = _seg(
          clientId: 'brand-new-uuid', // backend omitted client_id
          id: 42,
          updatedAt: remoteUpdatedAt,
        );

        // findByRemoteId returns local; findByClientId('brand-new-uuid') → null.
        when(() => mockStore.findByRemoteId('42'))
            .thenAnswer((_) async => local);
        when(() => mockStore.findByClientId(any()))
            .thenAnswer((_) async => null);

        final ctx = await _run(_ctx([remote]));

        expect(ctx.safeToUpsert, hasLength(1));
        expect(ctx.conflicts, isEmpty);
        // The resolved clientId must be the LOCAL one.
        expect(ctx.safeToUpsert.first.clientId, equals('local-cid'));
        // The remote payload is preserved.
        expect(ctx.safeToUpsert.first.remote.id, equals(42));
        // The local copy is carried.
        expect(ctx.safeToUpsert.first.local, isNotNull);
      },
    );

    test(
      '(b) match by remoteId, local is NEWER → conflicts',
      () async {
        final localUpdatedAt = DateTime(2026, 1, 1); // newer
        final remoteUpdatedAt = DateTime(2025, 1, 1);

        final local = _seg(
          clientId: 'local-cid',
          id: 42,
          updatedAt: localUpdatedAt,
        );
        final remote = _seg(
          clientId: 'brand-new-uuid',
          id: 42,
          updatedAt: remoteUpdatedAt,
        );

        when(() => mockStore.findByRemoteId('42'))
            .thenAnswer((_) async => local);
        when(() => mockStore.findByClientId(any()))
            .thenAnswer((_) async => null);

        final ctx = await _run(_ctx([remote]));

        expect(ctx.conflicts, hasLength(1));
        expect(ctx.safeToUpsert, isEmpty);
        expect(ctx.conflicts.first.clientId, equals('local-cid'));
        expect(ctx.conflicts.first.local, isNotNull);
      },
    );

    test(
      '(c) matching job in PENDING → conflicts (cannot overwrite pending edit)',
      () async {
        final remoteUpdatedAt = DateTime(2026, 1, 1); // remote newer
        final localUpdatedAt = DateTime(2025, 1, 1);

        final local = _seg(
          clientId: 'local-cid',
          id: 42,
          updatedAt: localUpdatedAt,
        );
        final remote = _seg(
          clientId: 'brand-new-uuid',
          id: 42,
          updatedAt: remoteUpdatedAt,
        );

        when(() => mockStore.findByRemoteId('42'))
            .thenAnswer((_) async => local);
        when(() => mockStore.findByClientId(any()))
            .thenAnswer((_) async => null);

        // local-cid has a pending job → conflict regardless of timestamps
        when(() => mockQueue.pendingJobs(entityType: any(named: 'entityType')))
            .thenAnswer((_) async =>
                [_fakeJob(clientId: 'local-cid', status: SyncStatus.pending)]);

        final ctx = await _run(_ctx([remote]));

        expect(ctx.conflicts, hasLength(1));
        expect(ctx.safeToUpsert, isEmpty);
      },
    );

    test(
      '(d) matching job in SYNCING → conflicts (NF-4)',
      () async {
        final remoteUpdatedAt = DateTime(2026, 1, 1); // remote newer
        final localUpdatedAt = DateTime(2025, 1, 1);

        final local = _seg(
          clientId: 'local-cid',
          id: 42,
          updatedAt: localUpdatedAt,
        );
        final remote = _seg(
          clientId: 'brand-new-uuid',
          id: 42,
          updatedAt: remoteUpdatedAt,
        );

        when(() => mockStore.findByRemoteId('42'))
            .thenAnswer((_) async => local);
        when(() => mockStore.findByClientId(any()))
            .thenAnswer((_) async => null);

        // local-cid is currently being synced → should still conflict
        when(() => mockQueue.syncingJobs(entityType: any(named: 'entityType')))
            .thenAnswer((_) async =>
                [_fakeJob(clientId: 'local-cid', status: SyncStatus.syncing)]);

        final ctx = await _run(_ctx([remote]));

        expect(ctx.conflicts, hasLength(1),
            reason: 'NF-4: syncing clientIds must be treated as conflicting');
        expect(ctx.safeToUpsert, isEmpty);
      },
    );

    test(
      '(e) no match by remoteId nor by clientId → safeToUpsert (new item)',
      () async {
        final remote = _seg(
          clientId: 'totally-new-uuid',
          id: 99,
          updatedAt: DateTime(2025),
        );

        when(() => mockStore.findByRemoteId('99'))
            .thenAnswer((_) async => null);
        when(() => mockStore.findByClientId(any()))
            .thenAnswer((_) async => null);

        final ctx = await _run(_ctx([remote]));

        expect(ctx.safeToUpsert, hasLength(1));
        expect(ctx.conflicts, isEmpty);
        expect(ctx.safeToUpsert.first.clientId, equals('totally-new-uuid'));
        expect(ctx.safeToUpsert.first.local, isNull);
      },
    );

    test(
      '(f) ResolvedPullItem carries the LOCAL clientId for safeToUpsert',
      () async {
        final local = _seg(
          clientId: 'stable-local-cid',
          id: 7,
          updatedAt: DateTime(2025, 1, 1),
        );
        final remote = _seg(
          clientId: 'fresh-uuid-from-backend',
          id: 7,
          updatedAt: DateTime(2026, 1, 1), // remote newer
        );

        when(() => mockStore.findByRemoteId('7'))
            .thenAnswer((_) async => local);
        when(() => mockStore.findByClientId(any()))
            .thenAnswer((_) async => null);

        final ctx = await _run(_ctx([remote]));

        expect(ctx.safeToUpsert, hasLength(1));
        final item = ctx.safeToUpsert.first;
        expect(item.clientId, equals('stable-local-cid'),
            reason: 'must use the local clientId, not the reminted one');
        expect(item.remote.id, equals(7),
            reason: 'remote payload is preserved');
        expect(item.local?.clientId, equals('stable-local-cid'),
            reason: 'local copy is carried without extra DB lookup');
      },
    );
  });
}
