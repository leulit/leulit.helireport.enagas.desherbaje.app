import 'package:flutter/foundation.dart';
import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';
import 'package:sqflite/sqflite.dart';

import '../data/local/local_database.dart';
import '../data/network/network_service.dart';
import '../data/repository/auth_repository_impl.dart';
import '../data/services/json_loader_service.dart';
import '../data/model/mensaje_entity.dart';
import '../data/sync/imagen_local_store.dart';
import '../data/sync/imagen_remote_adapter.dart';
import '../data/sync/mensaje_local_store.dart';
import '../data/sync/video_local_store.dart';
import '../data/sync/video_remote_adapter.dart';
import '../data/sync/mensaje_remote_adapter.dart';
import '../data/sync/position_batch_remote_adapter.dart';
import '../data/sync/position_local_store.dart';
import '../data/sync/posicion_fija_local_store.dart';
import '../data/sync/posicion_fija_remote_fetcher.dart';
import '../data/sync/segmento_local_store.dart';
import '../data/sync/segmento_remote_adapter.dart';
import '../data/sync/segmento_remote_fetcher.dart';
import '../domain/entities/imagen_segmento_entity.dart';
import '../domain/entities/position_batch_entity.dart';
import '../domain/entities/posicion_fija_entity.dart';
import '../domain/entities/segmento_entity.dart';
import '../domain/entities/video_segmento_entity.dart';
import 'services/auth_expiration_handler.dart';
import 'services/connectivity_service.dart';
import 'services/gasoductos_service.dart';
import 'services/gps_background_service.dart';
import 'services/pks_service.dart';
import 'services/hitos_service.dart';
import 'services/session_state.dart';
import 'sync/sync.dart';

class AppDI {
  /// Completer compartido: la 2ª llamada concurrent o secuencial reutiliza el
  /// mismo Future. Llamar [resetForTest] antes de un re-init (solo en tests /
  /// flujo retry del splash: el splash llama resetForTest() → init() de nuevo).
  static Future<void>? _initFuture;

  static Future<void> init() => _initFuture ??= _init();

  /// Limpia el completer para que la siguiente llamada a [init] vuelva a
  /// ejecutar [_init] desde cero. Llamado desde [SplashController.retry]
  /// cuando el bootstrap anterior terminó en error.
  static void reset() => _initFuture = null;

  /// Alias de [reset] para tests que necesiten restablecer el estado entre
  /// casos de prueba.
  @visibleForTesting
  static void resetForTest() => reset();

  static Future<void> _init() async {
    // 1. SessionState MUST be registered BEFORE any code calls AppDI.sessionState.
    //    AuthMiddleware.redirect is synchronous and reads hasSession directly.
    DI.registerLazySingleton<SessionState>(() => SessionState());

    // 2. TypeRegistry — register ONCE (was erroneously duplicated).
    DI.registerLazySingleton<TypeRegistry>(() => TypeRegistry());

    try {
      final isAuth = await AuthRepositoryImpl().isAuthenticated();
      AppDI.sessionState.set(isAuth);
    } catch (_) {
      // secure_storage unavailable (e.g. first install or permission error) →
      // treat as unauthenticated; do not block startup.
      AppDI.sessionState.set(false);
    }

    // 3. ConnectivityService — onInit is async (listens to connectivity stream).
    DI.registerSingletonAsync<ConnectivityService>(() async {
      final s = ConnectivityService();
      await s.onInit();
      return s;
    });

    // 4. NetworkService — onInit is sync (sets up Dio + interceptors).
    DI.registerSingletonAsync<NetworkService>(() async {
      final s = NetworkService();
      s.onInit();
      return s;
    });

    await DI.allReady();

    DI.registerLazySingleton<JsonLoaderService>(() => JsonLoaderService());
    // get_it NO dispara el lifecycle de GetxService: hay que llamar onInit() a
    // mano o estos services nunca se suscriben a geoJsonLoaded/Completed y el
    // progreso queda en 0/N con _entitiesBuffer vacío (descarga sin efecto).
    DI.registerLazySingleton<GasoductosService>(() => GasoductosService()..onInit());
    DI.registerLazySingleton<PksService>(() => PksService()..onInit());
    DI.registerLazySingleton<HitosService>(() => HitosService()..onInit());

    // 5. AuthExpirationHandler — sync onInit registers the TypedAction listener.
    //    Must be a singleton so the listener survives for the app lifetime.
    final handler = AuthExpirationHandler();
    handler.onInit();
    DI.registerSingleton<AuthExpirationHandler>(handler);

    // 6. Database — timeout 15s; error surfaces to SplashController.
    final db = await LocalDatabase.instance.database.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw Exception(
          'La base de datos SQLite no responde tras 15 segundos.',
        );
      },
    );
    DI.registerLazySingleton<Database>(() => db);

    // 7. OutboxQueue — ONE instance, registered as singleton.
    //    Previous code created two instances (local var + lazy registration) — bug.
    final outbox = OutboxQueue(db);
    DI.registerLazySingleton<OutboxQueue>(() => outbox);

    // 8. SyncEngine reuses the same outbox singleton.
    DI.registerLazySingleton<SyncEngine>(
      () => SyncEngine(
        outbox: outbox,
        registry: AppDI.typeRegistry,
        db: db,
      ),
    );

    await _registerEntities(db);
  }

  // ─────────────────────────── Getters (resolve from DI) ───────────────────

  static NetworkService get networkService => di.get<NetworkService>();

  static GasoductosService get gasoductosService =>
      di.get<GasoductosService>();

  static PksService get pksService => di.get<PksService>();

  static HitosService get hitosService => di.get<HitosService>();

  static OutboxQueue get outboxQueue => di.get<OutboxQueue>();

  static SyncEngine get syncEngine => di.get<SyncEngine>();

  static ConnectivityService get connectivityService =>
      di.get<ConnectivityService>();

  static SessionState get sessionState => di.get<SessionState>();

  static JsonLoaderService get jsonLoaderService =>
      di.get<JsonLoaderService>();

  static TypeRegistry get typeRegistry => di.get<TypeRegistry>();

  static Database get database => di.get<Database>();

  // ─────────────────────────── Entity registration ─────────────────────────

  static Future<void> _registerEntities(Database db) async {
    // All global services resolved from DI (not GetX container).
    final network = DI.get<NetworkService>();

    final segmentoStore = SegmentoLocalStore(db);
    DI.registerLazySingleton<SegmentoLocalStore>(() => segmentoStore);
    await OfflineModule.registerEntity<SegmentoEntity>(
      entityType: 'segmento',
      store: segmentoStore,
      adapter: SegmentoRemoteAdapter(network),
      fetcher: SegmentoRemoteFetcher(network),
      conflictResolver: const InteractiveConflictResolver<SegmentoEntity>(),
      fromJson: SegmentoEntity.fromJson,
      formatForDisplay: _formatSegmentoForDisplay,
    );

    final imagenStore = ImagenLocalStore(db);
    DI.registerLazySingleton<ImagenLocalStore>(() => imagenStore);
    await OfflineModule.registerEntity<ImagenSegmentoEntity>(
      entityType: 'imagen',
      store: imagenStore,
      adapter: ImagenRemoteAdapter(network),
      conflictResolver: const ServerWinsResolver<ImagenSegmentoEntity>(),
      fromJson: ImagenSegmentoEntity.fromJson,
    );

    final mensajeStore = MensajeLocalStore(db);
    DI.registerLazySingleton<MensajeLocalStore>(() => mensajeStore);
    await OfflineModule.registerEntity<MensajeSegmentoEntity>(
      entityType: 'mensaje',
      store: mensajeStore,
      adapter: MensajeRemoteAdapter(network),
      conflictResolver: const ServerWinsResolver<MensajeSegmentoEntity>(),
      fromJson: MensajeSegmentoEntity.fromJson,
    );

    final positionStore = PositionLocalStore(db);
    DI.registerLazySingleton<PositionLocalStore>(() => positionStore);
    await OfflineModule.registerEntity<PositionBatchEntity>(
      entityType: 'position_batch',
      store: positionStore,
      adapter: PositionBatchRemoteAdapter(network),
      conflictResolver: const ServerWinsResolver<PositionBatchEntity>(),
      fromJson: PositionBatchEntity.fromJson,
    );

    final videoStore = VideoLocalStore(db);
    DI.registerLazySingleton<VideoLocalStore>(() => videoStore);
    await OfflineModule.registerEntity<VideoSegmentoEntity>(
      entityType: 'video',
      store: videoStore,
      adapter: VideoRemoteAdapter(network, videoStore),
      conflictResolver: const ServerWinsResolver<VideoSegmentoEntity>(),
      fromJson: VideoSegmentoEntity.fromJson,
    );

    final posicionFijaStore = PosicionFijaLocalStore(db);
    DI.registerLazySingleton<PosicionFijaLocalStore>(() => posicionFijaStore);
    await OfflineModule.registerEntity<PosicionFijaEntity>(
      entityType: 'posicion_fija',
      store: posicionFijaStore,
      fetcher: PosicionFijaRemoteFetcher(network),
      conflictResolver: const ServerWinsResolver<PosicionFijaEntity>(),
      fromJson: PosicionFijaEntity.fromJson,
    );

    DI.registerLazySingleton<GpsBackgroundService>(() => GpsBackgroundService());
  }

  static Map<String, String> _formatSegmentoForDisplay(SegmentoEntity s) => {
        'CT': s.ctname,
        'Nombre': s.nombre ?? '—',
        'Traza': s.traza ?? '—',
        'Estado': s.estado.etiqueta,
        'Tipo': s.tipoActividad.etiqueta,
        'PK Inicio': s.pkInicio?.toStringAsFixed(3) ?? '—',
        'PK Fin': s.pkFin?.toStringAsFixed(3) ?? '—',
        'Longitud': '${s.longitudKm.toStringAsFixed(2)} km',
      };
}
