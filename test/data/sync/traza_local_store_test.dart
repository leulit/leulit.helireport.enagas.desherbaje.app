import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/data/sync/traza_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/traza_entity.dart';

// ─── DB helpers ──────────────────────────────────────────────────────────────

Future<Database> _openDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(inMemoryDatabasePath, version: 1);
  final store = TrazaLocalStore(db);
  await store.migrate(db, 0, 1);
  return db;
}

TrazaEntity _makeTraza({
  required String clientId,
  required int operadorId,
  required DateTime startedAt,
  DateTime? endedAt,
  List<TrazaPunto>? points,
  String? name,
}) {
  return TrazaEntity(
    clientId: clientId,
    operadorId: operadorId,
    startedAt: startedAt,
    endedAt: endedAt,
    name: name,
    points: points ?? const [],
  );
}

TrazaPunto _point(DateTime t) =>
    TrazaPunto(capturedAt: t, lat: 40.0, lng: -3.0);

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late Database db;
  late TrazaLocalStore store;

  setUp(() async {
    db = await _openDb();
    store = TrazaLocalStore(db);
  });

  tearDown(() async => db.close());

  group('appendPoints', () {
    test('does not duplicate or lose points across multiple calls', () async {
      final base = DateTime.utc(2025, 6, 1, 10, 0);
      final traza = _makeTraza(
        clientId: 'traza-1',
        operadorId: 1,
        startedAt: base,
      );
      await store.upsert(traza);

      await store.appendPoints('traza-1', [
        _point(base),
        _point(base.add(const Duration(seconds: 30))),
      ]);
      await store.appendPoints('traza-1', [
        _point(base.add(const Duration(seconds: 60))),
      ]);

      final result = await store.findByClientId('traza-1');
      expect(result!.points.length, equals(3));
    });

    test(
        'appending existing points again duplicates rows (append-only, '
        'never dedups) — callers must not re-flush the same buffer', () async {
      final base = DateTime.utc(2025, 6, 1, 10, 0);
      final traza =
          _makeTraza(clientId: 'traza-dup', operadorId: 1, startedAt: base);
      await store.upsert(traza);

      final pts = [_point(base)];
      await store.appendPoints('traza-dup', pts);
      await store.appendPoints('traza-dup', pts);

      final result = await store.findByClientId('traza-dup');
      expect(result!.points.length, equals(2));
    });

    test('empty list is a no-op', () async {
      final base = DateTime.utc(2025, 6, 1, 10, 0);
      await store.upsert(
          _makeTraza(clientId: 'traza-empty', operadorId: 1, startedAt: base));
      await store.appendPoints('traza-empty', const []);

      final result = await store.findByClientId('traza-empty');
      expect(result!.points, isEmpty);
    });
  });

  group('findOpen', () {
    test('returns only the open traza (ended_at IS NULL) for the operator',
        () async {
      final base = DateTime.utc(2025, 6, 1, 8, 0);
      await store.upsert(_makeTraza(
        clientId: 'closed-1',
        operadorId: 10,
        startedAt: base,
        endedAt: base.add(const Duration(minutes: 5)),
      ));
      await store.upsert(_makeTraza(
        clientId: 'open-1',
        operadorId: 10,
        startedAt: base.add(const Duration(hours: 1)),
      ));
      await store.upsert(_makeTraza(
        clientId: 'open-other-operador',
        operadorId: 20,
        startedAt: base,
      ));

      final result = await store.findOpen(10);
      expect(result, isNotNull);
      expect(result!.clientId, equals('open-1'));
    });

    test('returns null when the operator has no open traza', () async {
      final base = DateTime.utc(2025, 6, 1, 8, 0);
      await store.upsert(_makeTraza(
        clientId: 'closed-only',
        operadorId: 5,
        startedAt: base,
        endedAt: base.add(const Duration(minutes: 1)),
      ));

      final result = await store.findOpen(5);
      expect(result, isNull);
    });
  });

  group('findAnyOpen', () {
    test('returns an open traza regardless of operador', () async {
      final base = DateTime.utc(2025, 6, 1, 8, 0);
      await store.upsert(_makeTraza(
        clientId: 'closed-1',
        operadorId: 1,
        startedAt: base,
        endedAt: base.add(const Duration(minutes: 1)),
      ));
      await store.upsert(_makeTraza(
        clientId: 'open-1',
        operadorId: 99,
        startedAt: base,
      ));

      final result = await store.findAnyOpen();
      expect(result, isNotNull);
      expect(result!.clientId, equals('open-1'));
    });

    test('returns null when there is no open traza at all', () async {
      final base = DateTime.utc(2025, 6, 1, 8, 0);
      await store.upsert(_makeTraza(
        clientId: 'closed-1',
        operadorId: 1,
        startedAt: base,
        endedAt: base.add(const Duration(minutes: 1)),
      ));

      expect(await store.findAnyOpen(), isNull);
    });
  });

  group('finalize', () {
    test('sets name and endedAt without touching points', () async {
      final base = DateTime.utc(2025, 6, 1, 9, 0);
      await store.upsert(_makeTraza(
        clientId: 'to-finalize',
        operadorId: 1,
        startedAt: base,
      ));
      await store.appendPoints('to-finalize', [_point(base)]);

      final endedAt = base.add(const Duration(minutes: 10));
      await store.finalize(
        trazaClientId: 'to-finalize',
        name: 'Traza de la tarde',
        endedAt: endedAt,
      );

      final result = await store.findByClientId('to-finalize');
      expect(result!.name, equals('Traza de la tarde'));
      expect(result.endedAt, isNotNull);
      expect(result.endedAt!.difference(endedAt).inSeconds.abs(), lessThan(1));
      expect(result.points.length, equals(1));
    });
  });

  group('deleteSynced', () {
    test('removes only trazas with synced_at set', () async {
      final base = DateTime.utc(2025, 6, 1, 8, 0);
      await store.upsert(_makeTraza(
        clientId: 'synced-1',
        operadorId: 1,
        startedAt: base,
        endedAt: base.add(const Duration(minutes: 1)),
      ));
      await store.appendPoints('synced-1', [_point(base)]);
      await store.markSynced(clientId: 'synced-1', remoteId: '42');

      await store.upsert(_makeTraza(
        clientId: 'pending-1',
        operadorId: 1,
        startedAt: base,
        endedAt: base.add(const Duration(minutes: 1)),
      ));

      final removed = await store.deleteSynced();
      expect(removed, equals(1));

      expect(await store.findByClientId('synced-1'), isNull);
      expect(await store.findByClientId('pending-1'), isNotNull);

      // Cascade removed the synced traza's points too.
      final orphanPoints = await db.query(
        'trazas_puntos',
        where: 'traza_client_id = ?',
        whereArgs: ['synced-1'],
      );
      expect(orphanPoints, isEmpty);
    });

    test('returns 0 when nothing is synced', () async {
      await store.upsert(_makeTraza(
        clientId: 'unsynced',
        operadorId: 1,
        startedAt: DateTime.utc(2025, 6, 1),
      ));
      expect(await store.deleteSynced(), equals(0));
    });
  });

  group('roundtrip', () {
    test('upsert → findByClientId round-trips correctly', () async {
      final base = DateTime.utc(2025, 6, 1, 9, 0);
      final traza = _makeTraza(
        clientId: 'rt-1',
        operadorId: 42,
        startedAt: base,
        points: [
          TrazaPunto(
              capturedAt: base.toUtc(),
              lat: 40.1,
              lng: -3.1,
              accuracyMeters: 5.0),
          TrazaPunto(
              capturedAt: base.add(const Duration(minutes: 1)).toUtc(),
              lat: 40.2,
              lng: -3.2),
        ],
      );

      await store.upsert(traza);
      final result = await store.findByClientId('rt-1');

      expect(result, isNotNull);
      expect(result!.clientId, equals('rt-1'));
      expect(result.operadorId, equals(42));
      expect(result.points.length, equals(2));
      expect(result.endedAt, isNull);
    });
  });

  group('findAll (2-query group-by)', () {
    test('groups points by traza and orders DESC by started_at', () async {
      final base = DateTime.utc(2025, 6, 1, 10, 0);
      await store.upsert(_makeTraza(
          clientId: 't1',
          operadorId: 1,
          startedAt: base,
          points: [_point(base)]));
      await store.upsert(_makeTraza(
        clientId: 't2',
        operadorId: 1,
        startedAt: base.add(const Duration(hours: 1)),
      ));

      final all = await store.findAll();
      expect(all.length, equals(2));
      expect(all[0].clientId, equals('t2'));
      expect(all[1].clientId, equals('t1'));
      expect(all[1].points.length, equals(1));
      expect(all[0].points, isEmpty);
    });
  });

  group('NF-24 bad updated_at falls back to endedAt, not now()', () {
    test('row with updated_at=garbage returns updatedAt == endedAt', () async {
      final now = DateTime.utc(2025, 6, 1, 12, 0, 0);
      final endedAt = now.add(const Duration(minutes: 5));
      await store.upsert(_makeTraza(
        clientId: 'bad-updated',
        operadorId: 1,
        startedAt: now,
        endedAt: endedAt,
      ));

      await db.rawUpdate(
        "UPDATE trazas SET updated_at = 'not-a-date' "
        "WHERE traza_client_id = 'bad-updated'",
      );

      final result = await store.findByClientId('bad-updated');
      expect(
        result!.updatedAt.difference(endedAt).inSeconds.abs(),
        lessThan(1),
      );
    });
  });
}
