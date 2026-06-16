import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';

import 'package:helireport_desherbaje/core/result/data_result.dart';
import 'package:helireport_desherbaje/core/sync/sync.dart';
import 'package:helireport_desherbaje/data/repository/segmento_repository_impl.dart';
import 'package:helireport_desherbaje/data/sync/segmento_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockOfflineRepository extends Mock
    implements OfflineRepository<SegmentoEntity> {}

class _MockSegmentoLocalStore extends Mock implements SegmentoLocalStore {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SegmentoEntity _makeSegmento({int? id}) {
  final s = SegmentoEntity(id, 1, TipoInstalacion.lineal, []);
  s.estado = EstadoActividad.ejecucion;
  s.tipoActividad = TipoActividad.desherbajeSelectivo;
  s.descripcion = 'test';
  return s;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockOfflineRepository mockOffline;
  late _MockSegmentoLocalStore mockStore;
  late SegmentoRepositoryImpl repo;

  setUpAll(() {
    registerFallbackValue(_makeSegmento());
    registerFallbackValue(EstadoActividad.propuesta);
  });

  setUp(() {
    Get.reset();
    mockOffline = _MockOfflineRepository();
    mockStore = _MockSegmentoLocalStore();
    repo = SegmentoRepositoryImpl(offline: mockOffline, store: mockStore);
  });

  tearDown(Get.reset);

  // ─── (a) saveLocal id==null → create + job 'create' ──────────────────────

  test('(a) saveLocal con id==null delega a offline.create', () async {
    final segmento = _makeSegmento(id: null);
    when(() => mockOffline.create(any())).thenAnswer((_) async {});

    await repo.saveLocal(segmento);

    verify(() => mockOffline.create(any())).called(1);
    verifyNever(() => mockOffline.update(any()));
  });

  // ─── (b) saveLocal id!=null → update + job 'update' ──────────────────────

  test('(b) saveLocal con id!=null delega a offline.update', () async {
    final segmento = _makeSegmento(id: 42);
    when(() => mockOffline.update(any())).thenAnswer((_) async {});

    await repo.saveLocal(segmento);

    verify(() => mockOffline.update(any())).called(1);
    verifyNever(() => mockOffline.create(any()));
  });

  // ─── (c) updateEstado(idInexistente) → failure 404 ───────────────────────

  test('(c) updateEstado con id inexistente devuelve failure 404', () async {
    when(() => mockStore.findByRemoteId('99')).thenAnswer((_) async => null);

    final result = await repo.updateEstado(99, EstadoActividad.ejecucion);

    expect(result.isSuccess, isFalse);
    expect((result as DataFailure).statusCode, equals(404));
    verifyNever(() => mockOffline.update(any()));
  });

  // ─── (d) updateEstado con segmento existente → success ───────────────────

  test('(d) updateEstado con segmento existente actualiza estado y devuelve success',
      () async {
    final segmento = _makeSegmento(id: 10);
    when(() => mockStore.findByRemoteId('10'))
        .thenAnswer((_) async => segmento);
    when(() => mockOffline.update(any())).thenAnswer((_) async {});

    final result = await repo.updateEstado(10, EstadoActividad.finalizada);

    expect(result.isSuccess, isTrue);
    expect((result as DataSuccess<bool>).data, isTrue);
    verify(() => mockOffline.update(any())).called(1);
  });
}
