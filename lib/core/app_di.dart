import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../data/local/local_database.dart';
import '../data/network/network_service.dart';
import '../data/services/json_loader_service.dart';
import '../data/model/mensaje_entity.dart';
import '../data/sync/imagen_local_store.dart';
import '../data/sync/imagen_remote_adapter.dart';
import '../data/sync/mensaje_local_store.dart';
import '../data/sync/mensaje_remote_adapter.dart';
import '../data/sync/position_batch_remote_adapter.dart';
import '../data/sync/position_local_store.dart';
import '../data/sync/segmento_local_store.dart';
import '../data/sync/segmento_remote_adapter.dart';
import '../data/sync/segmento_remote_fetcher.dart';
import '../domain/entities/imagen_segmento_entity.dart';
import '../domain/entities/position_batch_entity.dart';
import '../domain/entities/segmento_entity.dart';
import 'services/auth_expiration_handler.dart';
import 'services/connectivity_service.dart';
import 'services/gasoductos_service.dart';
import 'services/gps_background_service.dart';
import 'services/gps_service.dart';
import 'services/pks_service.dart';
import 'sync/sync.dart';

class AppDI {
  /// Completer compartido: la 2ª llamada concurrent o secuencial reutiliza el
  /// mismo Future. Llamar [resetForTest] antes de un re-init (solo en tests /
  /// flujo retry del splash: el splash llama resetForTest() → init() de nuevo).
  static Future<void>? _initFuture;

  static Future<void> init() => _initFuture ??= _init();

  /// Limpia el completer para que la siguiente llamada a [init] vuelva a
  /// ejecutar [_init] desde cero. Usado en tests y en el flujo de reintento
  /// del splash cuando un bootstrap anterior terminó en error.
  // ignore: invalid_use_of_visible_for_testing_member — llamado legítimamente
  // por SplashController.retry() en producción.
  static void resetForTest() => _initFuture = null;

  static Future<void> _init() async {
    Get.put<TypeRegistry>(TypeRegistry(), permanent: true);
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
    Get.put<AuthExpirationHandler>(AuthExpirationHandler(), permanent: true);
    // Le ponemos un timeout de 15 segundos. Si en 15s no abre, lanzará un error y sabremos que es aquí.
    final db = await LocalDatabase.instance.database.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw Exception("La base de datos SQLite no responde tras 15 segundos.");
      },
    );
    Get.put<Database>(db, permanent: true);
    final outbox = OutboxQueue(db);
    Get.put<OutboxQueue>(outbox, permanent: true);
    Get.put<SyncEngine>(
      SyncEngine(
        outbox: outbox,
        registry: Get.find<TypeRegistry>(),
        db: db,
      ),
      permanent: true,
    );
    await _registerEntities(db);
  }

  static Future<void> _registerEntities(Database db) async {
    final network = Get.find<NetworkService>();

    final segmentoStore = SegmentoLocalStore(db);
    Get.put<SegmentoLocalStore>(segmentoStore, permanent: true);
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
    Get.put<ImagenLocalStore>(imagenStore, permanent: true);
    await OfflineModule.registerEntity<ImagenSegmentoEntity>(
      entityType: 'imagen',
      store: imagenStore,
      adapter: ImagenRemoteAdapter(network),
      conflictResolver: const ServerWinsResolver<ImagenSegmentoEntity>(),
      fromJson: ImagenSegmentoEntity.fromJson,
    );

    final mensajeStore = MensajeLocalStore(db);
    Get.put<MensajeLocalStore>(mensajeStore, permanent: true);
    await OfflineModule.registerEntity<MensajeSegmentoEntity>(
      entityType: 'mensaje',
      store: mensajeStore,
      adapter: MensajeRemoteAdapter(network),
      conflictResolver: const ServerWinsResolver<MensajeSegmentoEntity>(),
      fromJson: MensajeSegmentoEntity.fromJson,
    );

    final positionStore = PositionLocalStore(db);
    Get.put<PositionLocalStore>(positionStore, permanent: true);
    await OfflineModule.registerEntity<PositionBatchEntity>(
      entityType: 'position_batch',
      store: positionStore,
      adapter: PositionBatchRemoteAdapter(network),
      conflictResolver: const ServerWinsResolver<PositionBatchEntity>(),
      fromJson: PositionBatchEntity.fromJson,
    );

    Get.put<GpsBackgroundService>(GpsBackgroundService(), permanent: true);
  }

  static Map<String, String> _formatSegmentoForDisplay(SegmentoEntity s) => {
        'CT': s.ctId.toString(),
        'Nombre': s.nombre ?? '—',
        'Traza': s.traza ?? '—',
        'Estado': s.estado.etiqueta,
        'Tipo': s.tipoActividad.etiqueta,
        'PK Inicio': s.pkInicio?.toStringAsFixed(3) ?? '—',
        'PK Fin': s.pkFin?.toStringAsFixed(3) ?? '—',
        'Longitud': '${s.longitudKm.toStringAsFixed(2)} km',
      };
}
