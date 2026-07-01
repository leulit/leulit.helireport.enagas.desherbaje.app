import 'package:flutter/foundation.dart';
import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';

import '../app_di.dart';
import 'contracts/conflict_resolver.dart';
import 'contracts/local_store.dart';
import 'contracts/remote_adapter.dart';
import 'contracts/remote_fetcher.dart';
import 'contracts/syncable.dart';
import 'database/offline_database.dart';
import 'pull/cancel_token.dart';
import 'pull/pull_coordinator.dart';
import 'pull/pull_progress.dart';
import 'repository/offline_repository.dart';
import 'type_registry.dart';

/// Single point of extension for registering an entity in the offline-first
/// engine.
///
/// Adding a new entity is mechanical: implement [LocalStore] (+ optionally
/// [RemoteAdapter] / [RemoteFetcher]) and call [registerEntity] once at
/// startup. No file in this package needs to be edited.
abstract class OfflineModule {
  /// Maps `entityType` to a thunk that runs the matching `PullCoordinator<T>`
  /// without exposing the generic parameter to callers. Lets the sync page
  /// iterate `TypeRegistry.registrations` and trigger pulls without knowing
  /// the concrete `T` for each entity.
  static final Map<
      String,
      Future<PullSummary> Function({
        CancelToken? token,
        void Function(PullProgress)? onProgress,
      })> _pullRunners = {};

  /// Runs the registered `PullCoordinator` for [entityType]. Returns null if
  /// the entity has no `RemoteFetcher` (i.e. it is not pulleable).
  static Future<PullSummary?> runPull(
    String entityType, {
    CancelToken? token,
    void Function(PullProgress)? onProgress,
  }) {
    final runner = _pullRunners[entityType];
    if (runner == null) return Future.value(null);
    return runner(token: token, onProgress: onProgress);
  }

  /// Returns the entity types that have a `RemoteFetcher` registered.
  static Iterable<String> get pulleableEntityTypes => _pullRunners.keys;

  /// FOR TESTS ONLY — registers a custom pull runner without requiring a full
  /// entity registration. Lets unit tests control the [PullSummary] returned
  /// by [runPull] without spinning up a real [PullCoordinator].
  ///
  /// Call [resetPullRunners] in `tearDown` to clean up.
  @visibleForTesting
  static void registerPullRunnerForTest(
    String entityType,
    Future<PullSummary> Function({CancelToken? token}) runner,
  ) {
    _pullRunners[entityType] =
        ({CancelToken? token, void Function(PullProgress)? onProgress}) =>
            runner(token: token);
  }

  /// FOR TESTS ONLY — removes all registered pull runners.
  @visibleForTesting
  static void resetPullRunners() {
    _pullRunners.clear();
  }

  /// Registers [T] in the [TypeRegistry], runs its schema migration, and
  /// binds the matching helpers into the DI container:
  /// - `OfflineRepository<T>` if [adapter] is provided.
  /// - `PullCoordinator<T>` if [fetcher] is provided.
  ///
  /// Required infrastructure expected in DI before calling:
  /// `Database`, `OutboxQueue`, `TypeRegistry`.
  ///
  /// At least one of [adapter] / [fetcher] must be non-null. An entity that
  /// is purely local (never reaches the backend) does not belong in the
  /// engine at all.
  ///
  /// [formatForDisplay] is required when [conflictResolver] is an
  /// [InteractiveConflictResolver]; the conflict diff view in the sync
  /// page uses it to render readable labels.
  static Future<void> registerEntity<T extends Syncable>({
    required String entityType,
    required LocalStore<T> store,
    required ConflictResolver<T> conflictResolver,
    required T Function(Map<String, dynamic>) fromJson,
    RemoteAdapter<T>? adapter,
    RemoteFetcher<T>? fetcher,
    Map<String, String> Function(T)? formatForDisplay,
  }) async {
    if (adapter == null && fetcher == null) {
      throw ArgumentError(
        'Type "$entityType" must declare adapter, fetcher, or both.',
      );
    }
    if (conflictResolver is InteractiveConflictResolver<T> &&
        formatForDisplay == null) {
      throw ArgumentError(
        'Type "$entityType" uses InteractiveConflictResolver and must '
        'provide formatForDisplay so the conflict UI can render a diff.',
      );
    }

    final registry = AppDI.typeRegistry;
    final db = AppDI.database;
    final outbox = AppDI.outboxQueue; // resolved from DI (not GetX)

    final registration = TypeRegistration<T>(
      entityType: entityType,
      store: store,
      adapter: adapter,
      fetcher: fetcher,
      conflictResolver: conflictResolver,
      fromJson: fromJson,
      formatForDisplay: formatForDisplay,
    );
    registry.register<T>(registration);

    await OfflineDatabase.migrateEntity(db, store);

    if (adapter != null) {
      DI.registerLazySingleton<OfflineRepository<T>>(
        () => OfflineRepository<T>(
          entityType: entityType,
          db: db,
          store: store,
          outbox: outbox,
        ),
      );
    }
    if (fetcher != null) {
      final coordinator = PullCoordinator<T>(
        registration: registration,
        outbox: outbox,
        db: db,
      );
      DI.registerSingleton<PullCoordinator<T>>(coordinator);
      _pullRunners[entityType] = ({
        CancelToken? token,
        void Function(PullProgress)? onProgress,
      }) =>
          coordinator.pullNow(token: token, onProgress: onProgress);
    }
  }
}
