// Tests for SegmentoDetalleController — PR-7 (WS3): #4, NF-P.
//
// Strategy: inject mock repos via the optional constructor parameters added
// in PR-7. Uses testWidgets + GetMaterialApp so Get.snackbar() resolves.
//
// ignore_for_file: invalid_use_of_protected_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:helireport_desherbaje/core/result/data_result.dart';
import 'package:helireport_desherbaje/core/services/connectivity_service.dart';
import 'package:helireport_desherbaje/core/services/gasoductos_service.dart';
import 'package:helireport_desherbaje/core/sync/sync.dart';
import 'package:helireport_desherbaje/data/model/mensaje_entity.dart';
import 'package:helireport_desherbaje/data/network/network_service.dart';
import 'package:helireport_desherbaje/data/repository/auth_repository_impl.dart';
import 'package:helireport_desherbaje/data/repository/imagen_repository_impl.dart';
import 'package:helireport_desherbaje/data/repository/mensaje_segmento_repository.dart';
import 'package:helireport_desherbaje/data/repository/segmento_repository_impl.dart';
import 'package:helireport_desherbaje/data/repository/video_repository_impl.dart';
import 'package:helireport_desherbaje/data/sync/mensaje_local_store.dart';
import 'package:helireport_desherbaje/data/sync/segmento_local_store.dart';
import 'package:helireport_desherbaje/domain/entities/imagen_segmento_entity.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';
import 'package:helireport_desherbaje/domain/entities/user_entity.dart';
import 'package:helireport_desherbaje/domain/entities/video_segmento_entity.dart';
import 'package:helireport_desherbaje/presentation/detalle/segmento_detalle_controller.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockOfflineSegmento extends Mock
    implements OfflineRepository<SegmentoEntity> {}

class _MockOfflineImagen extends Mock
    implements OfflineRepository<ImagenSegmentoEntity> {}

class _MockOfflineVideo extends Mock
    implements OfflineRepository<VideoSegmentoEntity> {}

class _MockOfflineMensaje extends Mock
    implements OfflineRepository<MensajeSegmentoEntity> {}

class _MockSegmentoLocalStore extends Mock implements SegmentoLocalStore {}

class _MockMensajeLocalStore extends Mock implements MensajeLocalStore {}

class _MockSyncEngine extends Mock implements SyncEngine {}

class _MockConnectivity extends Mock implements ConnectivityService {}

/// GasoductosService stub — no network / file I/O.
class _StubGasoductosService extends GasoductosService {
  @override
  Future<void> ensureLoaded() async {}
}

/// AuthRepositoryImpl stub — getCurrentUser returns null (no user needed).
class _StubAuthRepo extends AuthRepositoryImpl {
  @override
  Future<UserModel?> getCurrentUser() async => null;
}

/// NetworkService stub — not called in these tests (Dio init is harmless).
class _StubNetworkService extends NetworkService {}

/// MensajeSegmentoRepository stub — all 3 dependencies injected to avoid
/// Get.find calls; mensajesBySegmento returns empty list.
class _StubMensajeRepo extends MensajeSegmentoRepository {
  _StubMensajeRepo({
    required NetworkService network,
    required OfflineRepository<MensajeSegmentoEntity> offline,
    required MensajeLocalStore localStore,
  }) : super(network: network, offline: offline, localStore: localStore);

  @override
  Future<DataResult<List<MensajeSegmentoEntity>>> mensajesBySegmento({
    required int id,
  }) async =>
      DataResult.success(const []);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SegmentoEntity _makeSegmento({int? id, EstadoActividad? estado}) {
  final s = SegmentoEntity(id, 1, TipoInstalacion.lineal, []);
  s.estado = estado ?? EstadoActividad.ejecucion;
  s.tipoActividad = TipoActividad.desherbajeSelectivo;
  s.descripcion = 'desc';
  return s;
}

Widget _appWidget() => const GetMaterialApp(home: Scaffold(body: SizedBox()));

/// Builds the controller and directly sets its segmento/observable fields,
/// bypassing [myOnInit] to avoid Get.arguments and async side-effects.
SegmentoDetalleController _buildController({
  required SegmentoEntity segmento,
  required SegmentoRepositoryImpl segmentoRepo,
  required ImagenRepositoryImpl imagenRepo,
  required VideoRepositoryImpl videoRepo,
  required MensajeSegmentoRepository mensajeRepo,
}) {
  final ctrl = SegmentoDetalleController(
    authRepo: _StubAuthRepo(),
    segmentoRepo: segmentoRepo,
    imagenRepo: imagenRepo,
    videoRepo: videoRepo,
    mensajeRepo: mensajeRepo,
  );
  // Directly set state — myOnInit not called (avoids Get.arguments, Dio, etc.)
  ctrl.segmento = segmento;
  ctrl.estado.value = segmento.estado;
  ctrl.tipoActividad.value = segmento.tipoActividad;
  ctrl.descripcion.value = segmento.descripcion;
  return ctrl;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockOfflineSegmento mockOfflineSegmento;
  late _MockOfflineImagen mockOfflineImagen;
  late _MockOfflineVideo mockOfflineVideo;
  late _MockOfflineMensaje mockOfflineMensaje;
  late _MockSegmentoLocalStore mockSegmentoStore;
  late _MockMensajeLocalStore mockMensajeStore;
  late _MockSyncEngine mockEngine;
  late _MockConnectivity mockConnectivity;

  late SegmentoRepositoryImpl segmentoRepo;
  late ImagenRepositoryImpl imagenRepo;
  late VideoRepositoryImpl videoRepo;
  late MensajeSegmentoRepository mensajeRepo;

  setUpAll(() {
    registerFallbackValue(_makeSegmento());
    registerFallbackValue(EstadoActividad.propuesta);
    registerFallbackValue(
      ImagenSegmentoEntity(
        actividadId: 0,
        segmentoId: 0,
        tipoFoto: TipoFoto.antes,
        filename: 'test.jpg',
        ruta: '/tmp/test.jpg',
        capturadaAt: DateTime.now(),
      ),
    );
    registerFallbackValue(
      MensajeSegmentoEntity(segmentoId: 0, mensaje: '', enviadoPor: 0),
    );
    registerFallbackValue(
      VideoSegmentoEntity(
        actividadId: 0,
        segmentoId: 0,
        tipoVideo: TipoVideo.antes,
        filename: 'test.mp4',
        ruta: '/tmp/test.mp4',
        capturadaAt: DateTime.now(),
      ),
    );
  });

  setUp(() async {
    Get.reset();
    await DI.reset();
    SharedPreferences.setMockInitialValues({});

    mockOfflineSegmento = _MockOfflineSegmento();
    mockOfflineImagen = _MockOfflineImagen();
    mockOfflineVideo = _MockOfflineVideo();
    mockOfflineMensaje = _MockOfflineMensaje();
    mockSegmentoStore = _MockSegmentoLocalStore();
    mockMensajeStore = _MockMensajeLocalStore();
    mockEngine = _MockSyncEngine();
    mockConnectivity = _MockConnectivity();

    when(() => mockConnectivity.isConnected).thenReturn(false);

    when(() => mockOfflineSegmento.create(any())).thenAnswer((_) async {});
    when(() => mockOfflineSegmento.update(any())).thenAnswer((_) async {});
    when(() => mockOfflineSegmento.findAll()).thenAnswer((_) async => []);

    when(() => mockOfflineImagen.create(any())).thenAnswer((_) async {});
    when(() => mockOfflineImagen.findAll()).thenAnswer((_) async => []);

    when(() => mockOfflineVideo.create(any())).thenAnswer((_) async {});
    when(() => mockOfflineVideo.findAll()).thenAnswer((_) async => []);
    when(() => mockOfflineVideo.findWhere(any(), any()))
        .thenAnswer((_) async => []);

    segmentoRepo = SegmentoRepositoryImpl(
      offline: mockOfflineSegmento,
      store: mockSegmentoStore,
    );

    imagenRepo = ImagenRepositoryImpl(
      offline: mockOfflineImagen,
      engine: mockEngine,
      connectivity: mockConnectivity,
    );

    videoRepo = VideoRepositoryImpl(
      offline: mockOfflineVideo,
      engine: mockEngine,
      connectivity: mockConnectivity,
    );

    mensajeRepo = _StubMensajeRepo(
      network: _StubNetworkService(),
      offline: mockOfflineMensaje,
      localStore: mockMensajeStore,
    );

    // Register global services in DI — resolved via AppDI getters in constructors.
    DI.registerSingleton<NetworkService>(_StubNetworkService());
    DI.registerSingleton<GasoductosService>(_StubGasoductosService());
  });

  tearDown(() async {
    Get.reset();
    await DI.reset();
  });

  // ─── (a) #4 guardar con id==null → offline.create 1 vez, updateEstado NUNCA

  testWidgets(
    '(a) guardar con id==null llama offline.create y NO llama updateEstado',
    (tester) async {
      await tester.pumpWidget(_appWidget());
      await tester.pump();

      final segmento = _makeSegmento(id: null);
      final ctrl = _buildController(
        segmento: segmento,
        segmentoRepo: segmentoRepo,
        imagenRepo: imagenRepo,
        videoRepo: videoRepo,
        mensajeRepo: mensajeRepo,
      );

      await ctrl.guardar();
      // Pump past the snackbar 2s timer so the test frame is clean.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      verify(() => mockOfflineSegmento.create(any())).called(1);
      // updateEstado uses findByRemoteId in the store — must never be called.
      verifyNever(() => mockSegmentoStore.findByRemoteId(any()));
      expect(ctrl.isSaving.value, isFalse);
    },
  );

  // ─── (b) estado no editable → _validateEstado devuelve false ──────────────

  testWidgets(
    '(b) guardar con estado propuesta no llama saveLocal (estado no editable)',
    (tester) async {
      await tester.pumpWidget(_appWidget());
      await tester.pump();

      final segmento = _makeSegmento(id: 5, estado: EstadoActividad.propuesta);
      final ctrl = _buildController(
        segmento: segmento,
        segmentoRepo: segmentoRepo,
        imagenRepo: imagenRepo,
        videoRepo: videoRepo,
        mensajeRepo: mensajeRepo,
      );
      ctrl.estado.value = EstadoActividad.propuesta;

      await ctrl.guardar();
      await tester.pumpAndSettle();

      verifyNever(() => mockOfflineSegmento.create(any()));
      verifyNever(() => mockOfflineSegmento.update(any()));
    },
  );

  // ─── (c) NF-P _addImagen con segmentoId==0 → offline.create de imagen ────

  testWidgets(
    '(c) NF-P: saveLocal de imagen acepta segmentoId=0 (local-only, id remoto 0)',
    (tester) async {
      await tester.pumpWidget(_appWidget());
      await tester.pump();

      // Verifica que el repo de imagen NO rechaza segmentoId=0.
      // La corrección NF-P elimina el guard `if (segId == null) return` y
      // construye la entidad con `segmentoId: segmento.id ?? 0`.
      final imagen = ImagenSegmentoEntity(
        actividadId: 0,
        segmentoId: 0, // local-only, id remoto desconocido
        tipoFoto: TipoFoto.antes,
        filename: 'foto.jpg',
        ruta: '/tmp/foto.jpg',
        capturadaAt: DateTime.now(),
      );

      await imagenRepo.saveLocal(imagen);

      verify(() => mockOfflineImagen.create(any())).called(1);
    },
  );

  // ─── (d) saveLocal lanza → isSaving queda false ───────────────────────────

  testWidgets(
    '(d) cuando offline.create lanza excepción isSaving queda false',
    (tester) async {
      await tester.pumpWidget(_appWidget());
      await tester.pump();

      when(() => mockOfflineSegmento.create(any()))
          .thenThrow(Exception('DB error'));

      final segmento = _makeSegmento(id: null);
      final ctrl = _buildController(
        segmento: segmento,
        segmentoRepo: segmentoRepo,
        imagenRepo: imagenRepo,
        videoRepo: videoRepo,
        mensajeRepo: mensajeRepo,
      );

      await ctrl.guardar();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(ctrl.isSaving.value, isFalse);
      verify(() => mockOfflineSegmento.create(any())).called(1);
    },
  );
}
