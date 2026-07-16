import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:helireport_desherbaje/core/result/data_result.dart';
import 'package:helireport_desherbaje/core/sync/sync.dart';
import 'package:helireport_desherbaje/data/model/mensaje_entity.dart';
import 'package:helireport_desherbaje/data/repository/mensaje_segmento_repository.dart';

// The repository is now fully offline-first: reads go to the local store by
// the owning segmento's clientId, writes go through the offline engine. No
// network involved.

class _MockOfflineRepository extends Mock
    implements OfflineRepository<MensajeSegmentoEntity> {}

MensajeSegmentoEntity _msg({String? clientId, String seg = 'seg-1'}) =>
    MensajeSegmentoEntity(
      clientId: clientId,
      segmentoId: 0,
      segmentoClientId: seg,
      mensaje: 'hola',
    );

void main() {
  late _MockOfflineRepository offline;
  late MensajeSegmentoRepository repo;

  setUpAll(() => registerFallbackValue(_msg()));

  setUp(() {
    offline = _MockOfflineRepository();
    repo = MensajeSegmentoRepository(offline: offline);
  });

  group('getAllBySegmentoClientId', () {
    test('delegates to offline.findWhere by segmento_client_id', () async {
      final rows = [_msg(clientId: 'a'), _msg(clientId: 'b')];
      when(() => offline.findWhere('segmento_client_id', 'seg-1'))
          .thenAnswer((_) async => rows);

      final result = await repo.getAllBySegmentoClientId('seg-1');

      expect(result, rows);
      verify(() => offline.findWhere('segmento_client_id', 'seg-1')).called(1);
    });
  });

  group('add', () {
    test('creates entity with segmentoClientId and enqueues via offline',
        () async {
      when(() => offline.create(any())).thenAnswer((_) async {});

      final result = await repo.add(
        segmentoId: 0,
        segmentoClientId: 'seg-9',
        mensaje: 'nuevo',
        enviadoPor: 7,
      );

      expect(result, isA<DataSuccess<MensajeSegmentoEntity>>());
      final captured = verify(() => offline.create(captureAny()))
          .captured
          .single as MensajeSegmentoEntity;
      expect(captured.segmentoClientId, 'seg-9');
      expect(captured.mensaje, 'nuevo');
      expect(captured.enviadoPor, 7);
      expect(captured.segmentoId, 0);
    });

    test('returns DataFailure when offline.create throws', () async {
      when(() => offline.create(any())).thenThrow(Exception('db locked'));

      final result = await repo.add(
        segmentoId: 1,
        segmentoClientId: 'seg-2',
        mensaje: 'x',
        enviadoPor: 1,
      );

      expect(result, isA<DataFailure<MensajeSegmentoEntity>>());
    });
  });
}
