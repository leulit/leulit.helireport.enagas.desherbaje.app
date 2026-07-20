// Tests for EditExtremosController — PR-7 (WS3) #4 hermano:
// guardar() persiste con id==null (sin guard id != null).
//
// Uses testWidgets + GetMaterialApp so Get.back() can resolve the navigator.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import 'package:helireport_desherbaje/core/services/gasoductos_service.dart';
import 'package:helireport_desherbaje/core/sync/sync.dart';
import 'package:helireport_desherbaje/data/repository/segmento_repository_impl.dart';
import 'package:helireport_desherbaje/data/sync/segmento_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';
import 'package:helireport_desherbaje/presentation/detalle/edit_extremos/edit_extremos_controller.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockOfflineRepository extends Mock
    implements OfflineRepository<SegmentoEntity> {}

class _MockSegmentoLocalStore extends Mock implements SegmentoLocalStore {}

class _StubGasoductosService extends GasoductosService {
  @override
  Future<void> ensureLoaded() async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SegmentoEntity _makeSegmento({int? id}) {
  final s = SegmentoEntity(id, 'CT1', TipoInstalacion.lineal, []);
  s.estado = EstadoActividad.ejecucion;
  s.tipoActividad = TipoActividad.posicionDesherbajeTraza;
  s.descripcion = 'test extremos';
  s.latInicio = 40.0;
  s.lngInicio = -3.0;
  s.latFin = 40.1;
  s.lngFin = -3.1;
  return s;
}

// ---------------------------------------------------------------------------
// Tests — wrapped in testWidgets so Get.back() has a navigator to pop
// ---------------------------------------------------------------------------

void main() {
  late _MockOfflineRepository mockOffline;
  late _MockSegmentoLocalStore mockStore;

  setUpAll(() {
    registerFallbackValue(_makeSegmento());
    registerFallbackValue(EstadoActividad.propuesta);
    registerFallbackValue(Polyline(points: const []));
  });

  setUp(() {
    Get.reset();
    mockOffline = _MockOfflineRepository();
    mockStore = _MockSegmentoLocalStore();

    when(() => mockOffline.create(any())).thenAnswer((_) async {});
    when(() => mockOffline.update(any())).thenAnswer((_) async {});
  });

  tearDown(Get.reset);

  // ─── Helper: wraps a body inside GetMaterialApp for navigator access ──────

  Widget appWithBody(Widget body) => GetMaterialApp(home: Scaffold(body: body));

  // ─── Guardar con id==null → offline.create (saveLocal ramifica create) ────

  testWidgets(
    'guardar con id==null llama a offline.create (saveLocal ramifica create)',
    (tester) async {
      final segmento = _makeSegmento(id: null);
      final repo = SegmentoRepositoryImpl(offline: mockOffline, store: mockStore);
      final controller = EditExtremosController(
        original: segmento,
        segmentoRepo: repo,
        gasoductos: _StubGasoductosService(),
      )..onInit();

      await tester.pumpWidget(appWithBody(const SizedBox()));
      await tester.pump();

      // Force hasChanges == true by changing fin position.
      controller.fin.value = const LatLng(41.0, -4.0);

      await controller.guardar();
      await tester.pumpAndSettle();

      verify(() => mockOffline.create(any())).called(1);
      verifyNever(() => mockOffline.update(any()));
    },
  );

  // ─── Guardar con id!=null → offline.update ────────────────────────────────

  testWidgets(
    'guardar con id!=null llama a offline.update (saveLocal ramifica update)',
    (tester) async {
      final segmento = _makeSegmento(id: 7);
      final repo = SegmentoRepositoryImpl(offline: mockOffline, store: mockStore);
      final controller = EditExtremosController(
        original: segmento,
        segmentoRepo: repo,
        gasoductos: _StubGasoductosService(),
      )..onInit();

      await tester.pumpWidget(appWithBody(const SizedBox()));
      await tester.pump();

      controller.fin.value = const LatLng(41.0, -4.0);

      await controller.guardar();
      await tester.pumpAndSettle();

      verify(() => mockOffline.update(any())).called(1);
      verifyNever(() => mockOffline.create(any()));
    },
  );

  // ─── Sin cambios → no llama a saveLocal ──────────────────────────────────

  testWidgets(
    'guardar sin cambios no llama a saveLocal',
    (tester) async {
      final segmento = _makeSegmento(id: 5);
      final repo = SegmentoRepositoryImpl(offline: mockOffline, store: mockStore);
      final controller = EditExtremosController(
        original: segmento,
        segmentoRepo: repo,
        gasoductos: _StubGasoductosService(),
      )..onInit();

      await tester.pumpWidget(appWithBody(const SizedBox()));
      await tester.pump();

      // hasChanges == false: no position changes.
      await controller.guardar();
      await tester.pumpAndSettle();

      verifyNever(() => mockOffline.create(any()));
      verifyNever(() => mockOffline.update(any()));
    },
  );
}
