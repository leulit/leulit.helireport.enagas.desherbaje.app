import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/data/sync/position_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/position_batch_entity.dart';

// ─── DB helpers ──────────────────────────────────────────────────────────────

Future<Database> _openDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(inMemoryDatabasePath, version: 1);
  final store = PositionLocalStore(db);
  await store.migrate(db, 0, 1);
  return db;
}

PositionBatchEntity _makeBatch({
  required String clientId,
  required int operadorId,
  required DateTime startedAt,
  required DateTime endedAt,
  List<PositionPoint>? points,
}) {
  return PositionBatchEntity(
    clientId: clientId,
    operadorId: operadorId,
    startedAt: startedAt,
    endedAt: endedAt,
    points: points ??
        [
          PositionPoint(
            capturedAt: startedAt,
            lat: 40.0,
            lng: -3.0,
          ),
        ],
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late Database db;
  late PositionLocalStore store;

  setUp(() async {
    db = await _openDb();
    store = PositionLocalStore(db);
  });

  tearDown(() async => db.close());

  // ─── NF-23: 2-query findAll ────────────────────────────────────────────────

  group('NF-23 findAll groups batches correctly (2 queries)', () {
    test('3 batches with 4/0/5 points — grouped and ordered', () async {
      final base = DateTime.utc(2025, 6, 1, 10, 0);

      final b1 = _makeBatch(
        clientId: 'b1',
        operadorId: 1,
        startedAt: base,
        endedAt: base.add(const Duration(minutes: 4)),
        points: List.generate(
          4,
          (i) => PositionPoint(
            capturedAt: base.add(Duration(minutes: i)),
            lat: 40.0 + i * 0.001,
            lng: -3.0,
          ),
        ),
      );
      final b2 = _makeBatch(
        clientId: 'b2',
        operadorId: 1,
        startedAt: base.add(const Duration(hours: 1)),
        endedAt: base.add(const Duration(hours: 1)),
        points: const [], // 0 points
      );
      final b3 = _makeBatch(
        clientId: 'b3',
        operadorId: 1,
        startedAt: base.add(const Duration(hours: 2)),
        endedAt: base.add(const Duration(hours: 2, minutes: 5)),
        points: List.generate(
          5,
          (i) => PositionPoint(
            capturedAt: base.add(Duration(hours: 2, minutes: i)),
            lat: 41.0 + i * 0.001,
            lng: -3.0,
          ),
        ),
      );

      await store.upsert(b1);
      await store.upsert(b2);
      await store.upsert(b3);

      final all = await store.findAll();

      // Ordered DESC by started_at: b3, b2, b1
      expect(all.length, equals(3));
      expect(all[0].clientId, equals('b3'));
      expect(all[1].clientId, equals('b2'));
      expect(all[2].clientId, equals('b1'));

      // Point counts
      expect(all[0].points.length, equals(5));
      expect(all[1].points.length, equals(0));
      expect(all[2].points.length, equals(4));

      // Points within batch b1 are ordered ASC by captured_at
      expect(
        all[2].points.first.capturedAt.isBefore(all[2].points.last.capturedAt),
        isTrue,
      );
      // Points within batch b3 are ordered ASC by captured_at
      expect(
        all[0].points.first.capturedAt.isBefore(all[0].points.last.capturedAt),
        isTrue,
      );
    });

    test('empty store returns empty list', () async {
      final all = await store.findAll();
      expect(all, isEmpty);
    });
  });

  // ─── NF-24: no fabricate updatedAt ────────────────────────────────────────

  group('NF-24 bad updated_at falls back to endedAt, not now()', () {
    test('row with updated_at=garbage returns updatedAt == endedAt', () async {
      final now = DateTime.utc(2025, 6, 1, 12, 0, 0);
      final batch = _makeBatch(
        clientId: 'bad-updated',
        operadorId: 1,
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 5)),
      );
      await store.upsert(batch);

      // Corrupt the updated_at after upsert
      await db.rawUpdate(
        "UPDATE posiciones_gps_batches SET updated_at = 'not-a-date' "
        "WHERE batch_client_id = 'bad-updated'",
      );

      final result = await store.findByClientId('bad-updated');
      expect(result, isNotNull);

      final endedAt = now.add(const Duration(minutes: 5));
      // updatedAt must equal endedAt (deterministic fallback), NOT ~now().
      expect(
        result!.updatedAt.difference(endedAt).inSeconds.abs(),
        lessThan(1),
        reason: 'updatedAt should equal endedAt, not DateTime.now()',
      );
    });
  });

  // ─── Roundtrip ─────────────────────────────────────────────────────────────

  group('roundtrip', () {
    test('upsert → findByClientId round-trips correctly', () async {
      final base = DateTime.utc(2025, 6, 1, 9, 0);
      final batch = _makeBatch(
        clientId: 'rt-1',
        operadorId: 42,
        startedAt: base,
        endedAt: base.add(const Duration(minutes: 3)),
        points: [
          PositionPoint(
            capturedAt: base.toUtc(),
            lat: 40.1,
            lng: -3.1,
            accuracyMeters: 5.0,
          ),
          PositionPoint(
            capturedAt: base.add(const Duration(minutes: 1)).toUtc(),
            lat: 40.2,
            lng: -3.2,
          ),
        ],
      );

      await store.upsert(batch);
      final result = await store.findByClientId('rt-1');

      expect(result, isNotNull);
      expect(result!.clientId, equals('rt-1'));
      expect(result.operadorId, equals(42));
      expect(result.points.length, equals(2));

      // startedAt should round-trip as UTC
      expect(result.startedAt.isUtc, isTrue);
    });

    test('startedAt.isUtc is true after roundtrip when stored as UTC', () async {
      final utcNow = DateTime.utc(2025, 6, 2, 10, 30);
      final batch = _makeBatch(
        clientId: 'utc-check',
        operadorId: 1,
        startedAt: utcNow,
        endedAt: utcNow.add(const Duration(minutes: 10)),
      );
      await store.upsert(batch);
      final result = await store.findByClientId('utc-check');
      expect(result!.startedAt.isUtc, isTrue);
    });
  });

  // ─── findAll with NF-24 ────────────────────────────────────────────────────

  group('NF-24 via findAll', () {
    test('bad updated_at in findAll falls back to endedAt', () async {
      final base = DateTime.utc(2025, 6, 3, 8, 0);
      final batch = _makeBatch(
        clientId: 'nf24-findall',
        operadorId: 1,
        startedAt: base,
        endedAt: base.add(const Duration(minutes: 7)),
      );
      await store.upsert(batch);

      await db.rawUpdate(
        "UPDATE posiciones_gps_batches SET updated_at = 'garbage' "
        "WHERE batch_client_id = 'nf24-findall'",
      );

      final all = await store.findAll();
      final found = all.firstWhere((b) => b.clientId == 'nf24-findall');

      final expected = base.add(const Duration(minutes: 7));
      expect(
        found.updatedAt.difference(expected).inSeconds.abs(),
        lessThan(1),
      );
    });
  });
}
