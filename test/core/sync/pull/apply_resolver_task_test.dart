// Tests for ApplyResolverTask — closes the gap between DetectConflictsTask
// (which never invoked the configured ConflictResolver) and the resolver
// contract. Focus: a deterministic resolver reclassifies the conflict into
// safeToUpsert and it never reaches sync_conflicts; InteractiveConflictResolver
// (the only one returning null) leaves the conflict untouched.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:helireport_desherbaje/core/sync/contracts/conflict_resolver.dart';
import 'package:helireport_desherbaje/core/sync/contracts/local_store.dart';
import 'package:helireport_desherbaje/core/sync/pull/pull_context.dart';
import 'package:helireport_desherbaje/core/sync/pull/tasks/apply_resolver_task.dart';
import 'package:helireport_desherbaje/core/sync/type_registry.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';
import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

class MockLocalStore extends Mock implements LocalStore<SegmentoEntity> {}

/// Resolver de prueba: siempre gana `local` — igual forma que
/// [LocalWinsResolver] pero instanciable con una identidad reconocible en
/// los asserts (no hace falta más para probar la reclasificación).
class _AlwaysLocalResolver implements ConflictResolver<SegmentoEntity> {
  const _AlwaysLocalResolver();

  @override
  SegmentoEntity resolve({
    required SegmentoEntity local,
    required SegmentoEntity remote,
  }) =>
      local;
}

TypeRegistration<SegmentoEntity> _registration(
  MockLocalStore store,
  ConflictResolver<SegmentoEntity> resolver,
) =>
    TypeRegistration<SegmentoEntity>(
      entityType: 'segmento',
      store: store,
      conflictResolver: resolver,
      fromJson: SegmentoEntity.fromJson,
    );

SegmentoEntity _seg({required String clientId, DateTime? updatedAt}) {
  final ts = (updatedAt ?? DateTime(2025)).toIso8601String();
  return SegmentoEntity.fromJson({
    'client_id': clientId,
    'ctname': 'CT1',
    'tipo_instalacion': 'lineal',
    'tipo_actividad': 'deshierbe_selectivo',
    'estado': 'propuesta',
    'descripcion': '',
    'updated_at': ts,
  });
}

void main() {
  setUpAll(() {
    registerFallbackValue(SegmentoEntity.empty());
  });

  Future<PullContext<SegmentoEntity>> runTask(
    PullContext<SegmentoEntity> ctx,
  ) async {
    final task = ApplyResolverTask<SegmentoEntity>();
    final result = await task.execute(DataPipeline.of(ctx));
    return result.output;
  }

  group('ApplyResolverTask', () {
    test(
      'resolver returns non-null → item moves from conflicts to safeToUpsert '
      'under the resolved entity, never reaches sync_conflicts territory',
      () async {
        final local = _seg(clientId: 'c1', updatedAt: DateTime(2026, 1, 1));
        final remote = _seg(clientId: 'c1', updatedAt: DateTime(2025, 1, 1));

        final ctx = PullContext<SegmentoEntity>(
          registration: _registration(MockLocalStore(), const _AlwaysLocalResolver()),
        );
        ctx.conflicts.add((remote: remote, clientId: 'c1', local: local));

        final result = await runTask(ctx);

        expect(result.conflicts, isEmpty,
            reason: 'resolved item must not stay in conflicts — that list '
                'feeds EnqueueConflictsTask → sync_conflicts');
        expect(result.safeToUpsert, hasLength(1));
        expect(result.safeToUpsert.first.clientId, 'c1');
        // The resolved entity (local, per _AlwaysLocalResolver) is the one
        // that gets persisted, not the raw remote payload.
        expect(result.safeToUpsert.first.remote, same(local));
        expect(result.safeToUpsert.first.local, same(local));
      },
    );

    test(
      'InteractiveConflictResolver (returns null) → item stays in conflicts '
      'unchanged, same as before this task existed',
      () async {
        final local = _seg(clientId: 'c2', updatedAt: DateTime(2026, 1, 1));
        final remote = _seg(clientId: 'c2', updatedAt: DateTime(2025, 1, 1));

        final ctx = PullContext<SegmentoEntity>(
          registration: _registration(
            MockLocalStore(),
            const InteractiveConflictResolver<SegmentoEntity>(),
          ),
        );
        ctx.conflicts.add((remote: remote, clientId: 'c2', local: local));

        final result = await runTask(ctx);

        expect(result.safeToUpsert, isEmpty);
        expect(result.conflicts, hasLength(1));
        expect(result.conflicts.first.clientId, 'c2');
        expect(result.conflicts.first.remote, same(remote));
      },
    );

    test('multiple conflicts: only the resolvable ones are reclassified',
        () async {
      final localA = _seg(clientId: 'a', updatedAt: DateTime(2026, 1, 1));
      final remoteA = _seg(clientId: 'a', updatedAt: DateTime(2025, 1, 1));
      final localB = _seg(clientId: 'b', updatedAt: DateTime(2026, 1, 1));
      final remoteB = _seg(clientId: 'b', updatedAt: DateTime(2025, 1, 1));

      final ctx = PullContext<SegmentoEntity>(
        registration: _registration(
          MockLocalStore(),
          const InteractiveConflictResolver<SegmentoEntity>(),
        ),
      );
      ctx.conflicts.add((remote: remoteA, clientId: 'a', local: localA));
      ctx.conflicts.add((remote: remoteB, clientId: 'b', local: localB));

      final result = await runTask(ctx);

      // InteractiveConflictResolver always returns null → both stay.
      expect(result.conflicts, hasLength(2));
      expect(result.safeToUpsert, isEmpty);
    });

    test('empty conflicts → no-op', () async {
      final ctx = PullContext<SegmentoEntity>(
        registration: _registration(
          MockLocalStore(),
          const InteractiveConflictResolver<SegmentoEntity>(),
        ),
      );

      final result = await runTask(ctx);

      expect(result.conflicts, isEmpty);
      expect(result.safeToUpsert, isEmpty);
    });
  });
}
