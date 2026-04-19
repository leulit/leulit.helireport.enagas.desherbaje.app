---
name: flutter-offline-sync
description: >
  Flutter offline-first and sync skill — use this whenever the project needs
  to work without internet connectivity, queue operations for later sync,
  detect network status, cache API responses locally, resolve conflicts between
  local and remote data, or implement background synchronization. Triggers on
  mentions of offline, sync, connectivity, local database, queue, cache,
  field work, no internet, background sync, or conflict resolution.
  Always apply alongside flutter-core and flutter-backend-integration.
---

# Flutter Offline Sync Skill

> Always apply **flutter-core** and **flutter-backend-integration** in parallel.

## Core Stack

| Package | Purpose |
|---|---|
| `drift: ^2.20.0` | SQLite ORM — typed queries, migrations, reactive streams |
| `connectivity_plus: ^6.0.0` | Network status detection (WiFi, mobile, none) |
| `get_storage: ^2.1.1` | Lightweight key-value for settings/tokens |
| `uuid: ^4.4.0` | Client-side ID generation for optimistic records |
| `workmanager: ^0.5.2` | Background task scheduling (iOS + Android) |

---

## Architecture: Offline-First Data Flow

```
User Action
    │
    ▼
Controller ──► LocalRepository (Drift) ──► UI updates immediately
    │
    ▼
SyncQueue (local DB table)
    │
    ▼ (when online)
SyncService ──► RemoteRepository (API) ──► Mark as synced / handle conflict
```

**Rule**: UI always reads from local DB. Remote is secondary.

---

## Connectivity Service

```dart
class ConnectivityService extends GetxService {
  final isOnline = false.obs;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  Future<ConnectivityService> init() async {
    // Check initial state
    final results = await Connectivity().checkConnectivity();
    isOnline.value = _isConnected(results);

    // Listen for changes
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final wasOffline = !isOnline.value;
      isOnline.value = _isConnected(results);

      if (wasOffline && isOnline.value) {
        // Came back online — trigger sync
        Get.find<SyncService>().syncPendingOperations();
      }
    });
    return this;
  }

  bool _isConnected(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }
}
```

---

## Local Database (Drift)

```dart
// data/local/app_database.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

// Tables
class InspectionRecords extends Table {
  TextColumn get id => text()(); // UUID — client-generated
  TextColumn get title => text()();
  TextColumn get data => text()(); // JSON blob for flexible schema
  IntColumn get status => integer().withDefault(const Constant(0))();
  // 0=draft, 1=pending_sync, 2=synced, 3=conflict
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get remoteId => text().nullable()(); // null until synced

  @override
  Set<Column> get primaryKey => {id};
}

class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()(); // 'inspection', 'report', etc.
  TextColumn get entityId => text()();   // local UUID
  TextColumn get operation => text()();  // 'create', 'update', 'delete'
  TextColumn get payload => text()();    // JSON
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [InspectionRecords, SyncQueue])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Handle schema migrations here
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(path.join(dir.path, 'app.sqlite'));
    return NativeDatabase(file);
  });
}
```

---

## Offline-First Repository Pattern

```dart
class InspectionRepository implements IInspectionRepository {
  final AppDatabase _db;
  final ApiProvider _api;
  final ConnectivityService _connectivity;

  InspectionRepository(this._db, this._api, this._connectivity);

  /// Always writes to local DB first, then queues for sync.
  @override
  Future<Either<Failure, InspectionEntity>> create(InspectionEntity entity) async {
    try {
      final id = const Uuid().v4();
      final record = InspectionRecordsCompanion.insert(
        id: id,
        title: entity.title,
        data: jsonEncode(entity.toJson()),
        status: const Value(1), // pending_sync
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _db.into(_db.inspectionRecords).insert(record);

      // Queue for sync
      await _queueOperation('inspection', id, 'create', entity.toJson());

      // If online, attempt immediate sync
      if (_connectivity.isOnline.value) {
        unawaited(_syncSingle(id));
      }

      return Right(entity.copyWith(id: id));
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  /// Read always comes from local DB — no network call.
  @override
  Stream<Either<Failure, List<InspectionEntity>>> watchAll() {
    return _db.select(_db.inspectionRecords).watch().map((rows) {
      try {
        final entities = rows
            .map((r) => InspectionEntity.fromJson(jsonDecode(r.data)))
            .toList();
        return Right<Failure, List<InspectionEntity>>(entities);
      } catch (e) {
        return Left<Failure, List<InspectionEntity>>(CacheFailure(e.toString()));
      }
    });
  }

  Future<void> _queueOperation(
    String entityType, String entityId,
    String operation, Map<String, dynamic> payload,
  ) async {
    await _db.into(_db.syncQueue).insert(SyncQueueCompanion.insert(
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: jsonEncode(payload),
      createdAt: DateTime.now(),
    ));
  }

  Future<void> _syncSingle(String localId) async { /* ... */ }
}
```

---

## Sync Service

```dart
class SyncService extends GetxService {
  final AppDatabase _db;
  final ApiProvider _api;
  final isSyncing = false.obs;
  final pendingCount = 0.obs;

  SyncService(this._db, this._api);

  Future<void> syncPendingOperations() async {
    if (isSyncing.value) return;
    isSyncing.value = true;

    try {
      final pending = await (_db.select(_db.syncQueue)
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

      pendingCount.value = pending.length;

      for (final item in pending) {
        await _processSyncItem(item);
      }
    } finally {
      isSyncing.value = false;
      await _updatePendingCount();
    }
  }

  Future<void> _processSyncItem(SyncQueueData item) async {
    // Max retry attempts: 3
    if (item.attempts >= 3) {
      await _markAsConflict(item);
      return;
    }

    // Update attempt count
    await (_db.update(_db.syncQueue)
      ..where((t) => t.id.equals(item.id)))
        .write(SyncQueueCompanion(
          attempts: Value(item.attempts + 1),
          lastAttemptAt: Value(DateTime.now()),
        ));

    try {
      final payload = jsonDecode(item.payload) as Map<String, dynamic>;
      Response response;

      switch (item.operation) {
        case 'create':
          response = await _api.post('/${item.entityType}s', payload);
        case 'update':
          response = await _api.put('/${item.entityType}s/${item.entityId}', payload);
        case 'delete':
          response = await _api.delete('/${item.entityType}s/${item.entityId}');
        default:
          return;
      }

      if (response.isOk) {
        // Remove from queue and mark entity as synced
        await (_db.delete(_db.syncQueue)
          ..where((t) => t.id.equals(item.id))).go();
        await _markEntitySynced(item.entityType, item.entityId,
            response.body?['id']?.toString());
        pendingCount.value = (pendingCount.value - 1).clamp(0, 999);
      }
    } catch (_) {
      // Will retry on next sync cycle
    }
  }

  Future<void> _markAsConflict(SyncQueueData item) async {
    // Mark local record as conflict for manual resolution
    if (item.entityType == 'inspection') {
      await (_db.update(_db.inspectionRecords)
        ..where((t) => t.id.equals(item.entityId)))
          .write(const InspectionRecordsCompanion(status: Value(3)));
    }
  }

  Future<void> _markEntitySynced(
      String type, String localId, String? remoteId) async {
    if (type == 'inspection') {
      await (_db.update(_db.inspectionRecords)
        ..where((t) => t.id.equals(localId)))
          .write(InspectionRecordsCompanion(
            status: const Value(2),
            remoteId: Value(remoteId),
          ));
    }
  }

  Future<void> _updatePendingCount() async {
    final count = await _db.syncQueue.count().getSingle();
    pendingCount.value = count;
  }
}
```

---

## Sync Status UI

```dart
// Always show sync status to field workers — they need to know
class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final connectivity = Get.find<ConnectivityService>();
    final sync = Get.find<SyncService>();

    return Obx(() {
      if (!connectivity.isOnline.value) {
        return const Chip(
          avatar: Icon(Icons.cloud_off, size: 16),
          label: Text('Offline'),
          backgroundColor: Colors.orange,
        );
      }
      if (sync.isSyncing.value) {
        return const Chip(
          avatar: SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: Text('Syncing...'),
        );
      }
      if (sync.pendingCount.value > 0) {
        return Chip(
          avatar: const Icon(Icons.sync_problem, size: 16),
          label: Text('${sync.pendingCount.value} pending'),
          backgroundColor: Colors.yellow.shade100,
        );
      }
      return const Chip(
        avatar: Icon(Icons.cloud_done, size: 16, color: Colors.green),
        label: Text('Synced'),
      );
    });
  }
}
```

---

## Background Sync (WorkManager)

```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  Workmanager().registerPeriodicTask(
    'background-sync',
    'syncPendingData',
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
  );
  runApp(const MyApp());
}

// Top-level callback — cannot use GetX here, access DB directly
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == 'syncPendingData') {
      final db = AppDatabase();
      final api = ApiProvider();
      // Minimal sync without full GetX context
      await _backgroundSync(db, api);
      await db.close();
    }
    return Future.value(true);
  });
}
```

---

## Conflict Resolution Strategy

Choose per project — document the decision in the codebase:

| Strategy | When to use |
|---|---|
| **Last-write-wins** | Simple data with no concurrent edits |
| **Server wins** | Server is always source of truth |
| **Client wins** | Field workers' data is authoritative |
| **Manual resolution** | When conflicts need user decision |

```dart
// Manual resolution: present conflict to user
Future<void> resolveConflict(String entityId) async {
  final local = await _getLocalVersion(entityId);
  final remote = await _getRemoteVersion(entityId);

  final choice = await Get.dialog<ConflictChoice>(
    ConflictResolutionDialog(local: local, remote: remote),
  );

  if (choice == ConflictChoice.keepLocal) {
    await _forceSync(entityId);
  } else {
    await _applyRemote(entityId, remote);
  }
}
```
