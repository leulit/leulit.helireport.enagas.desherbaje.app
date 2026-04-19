import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../data/local/local_database.dart';
import '../data/network/network_service.dart';
import '../data/services/json_loader_service.dart';
import '../data/sync/imagen_local_store.dart';
import '../data/sync/imagen_remote_adapter.dart';
import '../data/sync/segmento_local_store.dart';
import '../data/sync/segmento_remote_adapter.dart';
import '../domain/entities/imagen_segmento_entity.dart';
import '../domain/entities/segmento_entity.dart';
import 'services/connectivity_service.dart';
import 'services/gasoductos_service.dart';
import 'services/gps_service.dart';
import 'services/pks_service.dart';
import 'sync/sync.dart';

class AppDI {
  static Future<void> init() async {
    await Get.putAsync<ConnectivityService>(
      () async => ConnectivityService(),
      permanent: true,
    );
    await Get.putAsync<NetworkService>(
      () async => NetworkService(),
      permanent: true,
    );
    Get.put<GpsService>(GpsService(), permanent: true);
    Get.put<JsonLoaderService>(JsonLoaderService(), permanent: true);
    Get.put<GasoductosService>(GasoductosService(), permanent: true);
    Get.put<PksService>(PksService(), permanent: true);

    await _initSync();
  }

  static Future<void> _initSync() async {
    final db = await LocalDatabase.instance.database;
    final connectivity = Get.find<ConnectivityService>();
    final network = Get.find<NetworkService>();

    final registry = TypeRegistry();
    Get.put<TypeRegistry>(registry, permanent: true);
    final outbox = OutboxQueue(db);
    Get.put<OutboxQueue>(outbox, permanent: true);
    final engine = SyncEngine(
      outbox: outbox,
      registry: registry,
      isOnline: () => connectivity.isConnected,
    );
    Get.put<SyncEngine>(engine, permanent: true);
    engine.start();

    _registerSegmento(
      db: db,
      network: network,
      registry: registry,
      outbox: outbox,
      engine: engine,
      connectivity: connectivity,
    );
    _registerImagen(
      db: db,
      network: network,
      registry: registry,
      outbox: outbox,
      engine: engine,
      connectivity: connectivity,
    );

    final coordinator = BackgroundSyncCoordinator(
      outbox: outbox,
      engine: engine,
    );
    Get.put<BackgroundSyncCoordinator>(coordinator, permanent: true);
    await coordinator.start();
  }

  static void _registerSegmento({
    required Database db,
    required NetworkService network,
    required TypeRegistry registry,
    required OutboxQueue outbox,
    required SyncEngine engine,
    required ConnectivityService connectivity,
  }) {
    final store = SegmentoLocalStore(db);
    final adapter = SegmentoRemoteAdapter(network);
    registry.register<SegmentoEntity>(
      TypeRegistration<SegmentoEntity>(
        entityType: 'segmento',
        adapter: adapter,
        conflictResolver: const ServerWinsResolver<SegmentoEntity>(),
        fromJson: SegmentoEntity.fromJson,
        localStore: store,
      ),
    );
    Get.put<OfflineRepository<SegmentoEntity>>(
      OfflineRepository<SegmentoEntity>(
        entityType: 'segmento',
        db: db,
        store: store,
        outbox: outbox,
        engine: engine,
        isOnline: () => connectivity.isConnected,
      ),
      permanent: true,
    );
  }

  static void _registerImagen({
    required Database db,
    required NetworkService network,
    required TypeRegistry registry,
    required OutboxQueue outbox,
    required SyncEngine engine,
    required ConnectivityService connectivity,
  }) {
    final store = ImagenLocalStore(db);
    final adapter = ImagenRemoteAdapter(network);
    registry.register<ImagenSegmentoEntity>(
      TypeRegistration<ImagenSegmentoEntity>(
        entityType: 'imagen',
        adapter: adapter,
        conflictResolver: const ServerWinsResolver<ImagenSegmentoEntity>(),
        fromJson: ImagenSegmentoEntity.fromMap,
        localStore: store,
      ),
    );
    Get.put<OfflineRepository<ImagenSegmentoEntity>>(
      OfflineRepository<ImagenSegmentoEntity>(
        entityType: 'imagen',
        db: db,
        store: store,
        outbox: outbox,
        engine: engine,
        isOnline: () => connectivity.isConnected,
      ),
      permanent: true,
    );
  }
}
