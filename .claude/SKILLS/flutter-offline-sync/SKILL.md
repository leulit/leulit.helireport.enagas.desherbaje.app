---
name: flutter-offline-sync
description: >
  Flutter offline-first and background execution skill — use this whenever the
  project needs to keep working when the user minimises the app, locks the
  screen, or loses network: GPS/sensor streaming that survives backgrounding,
  writes that must never be lost offline, eventual sync with a backend,
  long-running uploads, state recovery after crash, conflict resolution, or
  any outbox-pattern implementation. Triggers on mentions of offline, sync,
  connectivity, background service, foreground service, isolate, workmanager,
  local database, queue, outbox, cache, field work, no internet, background
  sync, or conflict resolution. Always apply alongside flutter-core and
  flutter-backend-integration.
---

# Flutter Offline-First & Background Execution Skill

> Always apply **flutter-core** and **flutter-backend-integration** in parallel. This skill extends them for apps that must keep working when the user minimises them, locks the screen, or loses network.

## When this skill applies

Use this skill whenever the app needs any of the following:

- GPS/sensor streaming that survives backgrounding (field tools, tracking, delivery apps).
- Writes that must never be lost when offline (forms, inspections, photos).
- Eventual sync with a backend when connectivity returns.
- Long-running jobs (uploads, imports) that outlive a single Activity/Scene.
- State recovery after an app crash or OS kill.

Do **not** use this skill for lightweight caching (plain `cached_network_image` or `GetStorage`) — that's `flutter-core` territory.

---

## Core Stack

| Concern | Package | Notes |
|---|---|---|
| GPS / location | `geolocator` | Unified stream API; supports Android foreground notification and iOS background updates natively |
| Background isolate (Android) | `flutter_background_service` | Runs a Dart isolate inside a Foreground Service; survives Activity destruction |
| Periodic background jobs | `workmanager` | For scheduled/one-shot tasks (not streaming). Respects Doze |
| Connectivity | `connectivity_plus` | Emits `Stream<ConnectivityResult>`; wrap in a `ValueNotifier` for GetX reactivity |
| Local persistence (structured) | `sqflite` | WAL mode supports concurrent read/write from multiple isolates. This project uses `sqflite` directly |
| Local persistence (alternative) | `drift` | Typed queries, migrations, reactive streams (`.watch()`). Preferred when schema complexity warrants an ORM |
| Local persistence (KV) | `get_storage` / `shared_preferences` | For settings and tokens only — never for sync state |
| Client-side IDs | `uuid` | Required for idempotent sync (see §2.1) |
| Permissions | `permission_handler` | Use only for runtime requests; static permissions go in manifest/Info.plist |

---

## Non-Negotiable Principles

1. **Persist before you transmit.** Every user-generated change lands in local storage before any network call. The network is never on the critical path of the UX.
2. **The network is a detail.** The UI reads from local state. A background service reconciles with the backend. The two concerns must not share code paths.
3. **Every write is idempotent end-to-end.** The client assigns a stable `client_id` (UUID or local autoincrement). The backend keys on it. Duplicate sends must be harmless.
4. **Every outbound job is resumable.** A crash, kill or reboot must not lose state. The queue lives in SQLite, not in memory.
5. **Background code is adversarial.** Assume the OS will kill your process, revoke permissions, throttle CPU, and call your callbacks on unexpected threads. Log defensively, fail loudly.

---

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│ UI Layer (StatelessWidget + GetView<Controller>)           │
│   reads local state, never awaits the network              │
└─────────────┬──────────────────────────────────────────────┘
              │
┌─────────────▼──────────────────────────────────────────────┐
│ Domain Layer (use cases)                                   │
│   writes to local repository + enqueues a sync job         │
└─────────────┬──────────────────────────────────────────────┘
              │
┌─────────────▼──────────────────────────────────────────────┐
│ Data Layer                                                 │
│   ├── LocalRepository   (SQLite, truth of record offline) │
│   ├── OutboxQueue       (sync_queue table)                │
│   └── RemoteProvider    (HTTP, only invoked by SyncService)│
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│ SyncService (GetxService)                                  │
│   Timer + ConnectivityListener → drain OutboxQueue         │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│ BackgroundService (Android isolate)                        │
│   Foreground Service with own SQLite connection            │
│   Streams sensor/GPS data directly to local tables         │
└────────────────────────────────────────────────────────────┘
```

---

## 1. Background Execution

### 1.1 Platform matrix

| Need | Android | iOS |
|---|---|---|
| Streaming GPS in background | **Foreground Service** (`foregroundServiceType="location"`) + notification | `UIBackgroundModes=[location]` + `AppleSettings.allowBackgroundLocationUpdates` |
| Periodic job when app is closed | `workmanager` (respects Doze, min 15 min interval) | `BGTaskScheduler` via `workmanager` (best-effort, no guarantees) |
| Isolate in background | `flutter_background_service` (entry point with `@pragma('vm:entry-point')`) | Not needed — main isolate stays alive while location updates are delivered |
| Keep CPU awake during streaming | `WAKE_LOCK` permission + `ForegroundNotificationConfig.enableWakeLock: true` | Managed by iOS automatically while `UIBackgroundModes` is active |

**Rule of thumb**: on Android you need a second isolate to keep the stream alive across Activity teardown. On iOS you do not — configure `Info.plist` correctly and the main isolate keeps receiving callbacks.

### 1.2 Android foreground service

Do **not** request `ACCESS_BACKGROUND_LOCATION` unless you have a compelling, user-visible use case — Google Play reviews are aggressive and the feature is restricted. A Foreground Service of type `location` with a persistent notification is the correct pattern for field apps.

`AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />

<service
  android:name="id.flutter.flutter_background_service.BackgroundService"
  android:foregroundServiceType="location"
  android:stopWithTask="false"
  android:exported="false" />
```

### 1.3 iOS background location

`Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>fetch</string>
  <string>processing</string>
</array>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Needed while you use the app to record your route.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Needed so your route keeps recording when the app is in the background.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>Needed so your route keeps recording when the app is in the background.</string>
```

Location settings from Dart:

```dart
AppleSettings(
  accuracy: LocationAccuracy.high,
  distanceFilter: 5,
  activityType: ActivityType.otherNavigation,
  allowBackgroundLocationUpdates: true,
  showBackgroundLocationIndicator: true,      // the blue pill in the status bar
  pauseLocationUpdatesAutomatically: false,
);
```

### 1.4 Background isolate (Android)

```dart
// main.dart
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const channel = AndroidNotificationChannel(
    'tracking_channel',
    'Tracking',
    importance: Importance.low,              // no sound, no vibration
    enableVibration: false,
    playSound: false,
  );

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundServiceStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: channel.id,
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onBackgroundServiceStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<void> onBackgroundServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();  // critical — plugins reset in new isolate

  Database? db;                               // isolate-local connection
  StreamSubscription? positionSub;
  int? currentTrackId;

  service.on('startTracking').listen((event) async {
    currentTrackId = event?['trackId'] as int?;
    db = await _openIsolateDb();

    positionSub = Geolocator.getPositionStream(locationSettings: _settings).listen(
      (pos) async {
        await db!.insert('track_points', {
          'track_id': currentTrackId,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'accuracy': pos.accuracy,
          'timestamp': pos.timestamp.millisecondsSinceEpoch,
        });
        service.invoke('update', {
          'lat': pos.latitude, 'lng': pos.longitude,
        });
      },
      onError: (e) => service.invoke('error', {'message': e.toString()}),
    );
  });

  service.on('stopTracking').listen((_) async {
    await positionSub?.cancel();
    positionSub = null;
  });

  service.on('stopService').listen((_) async {
    await positionSub?.cancel();
    await db?.close();
    service.stopSelf();
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async => true;
```

Key rules:

- Always call `DartPluginRegistrant.ensureInitialized()` first — the isolate has no plugin bindings.
- Open a **separate** SQLite connection; do not try to share the main isolate's `Database` instance.
- Never `await` a main-isolate `Get.find<...>()` from inside the background entry point — it will not resolve.
- Communicate via `service.invoke(event, Map)` / `service.on(event).listen` — the payload must be JSON-serialisable.

### 1.5 Lifecycle-driven transitions

Use `AppLifecycleListener` (Flutter 3.13+) rather than `WidgetsBindingObserver` when you can — it has clearer semantics and supports cancellation.

```dart
class TrackingCoordinator {
  late final AppLifecycleListener _lifecycle;
  bool _isTransitioning = false;              // mutex, no await between check and set

  void _init() {
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
  }

  void _onLifecycle(AppLifecycleState s) {
    if (!_isTracking) return;
    if (s == AppLifecycleState.paused)   unawaited(_toBackground());
    if (s == AppLifecycleState.resumed)  unawaited(_toForeground());
  }

  Future<void> _toBackground() async {
    if (_isTransitioning) return;
    _isTransitioning = true;
    try {
      await _stateStore.save(state: 'activeBackground', trackId: _trackId);
      if (Platform.isAndroid) {
        _bgService.invoke('startTracking', {'trackId': _trackId, 'config': _config.toJson()});
        // keep ForegroundStrategy alive as fallback but stop persisting its points
      }
      // iOS: nothing — the main-isolate stream keeps flowing
    } finally {
      _isTransitioning = false;
    }
  }
}
```

Why the mutex: Android fires `inactive → paused` in quick succession, and `resumed` can race with a pending `startTracking` invoke. A boolean guard (no `await` between check and set) is sufficient because Dart is single-threaded per isolate.

### 1.6 Periodic background jobs (WorkManager)

For work that does **not** need a live stream — a nightly report upload, a daily cache cleanup, a best-effort outbox drain while the app is fully closed — use `workmanager` instead of a Foreground Service.

```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await Workmanager().registerPeriodicTask(
    'outbox-drain',
    'drainOutbox',
    frequency: const Duration(minutes: 15),          // OS floor; may fire later
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
  runApp(const MyApp());
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    // New isolate — GetX DI is empty here. Touch only what you explicitly open.
    if (task == 'drainOutbox') {
      final db = await _openOutboxDb();
      final api = ApiClient();                         // stateless
      try {
        await _drainOutboxStandalone(db, api);
      } finally {
        await db.close();
      }
    }
    return true;
  });
}
```

Rules:

- **Minimum interval 15 min** on both platforms; shorter values are silently raised.
- **No guarantees**: Doze, low battery, or user Force Stop may skip runs. Always complement with the in-app `SyncService` timer — never rely on WorkManager alone.
- The callback runs in a fresh isolate. **Do not** call `Get.find<...>()` there. Open dependencies manually and close them before returning.
- Keep the work idempotent — if the task runs twice back-to-back, the outcome must be the same.

---

## 2. Offline-First Data Flow

### 2.1 The outbox pattern

The outbox is a SQLite table of pending sync jobs. The UI writes to the domain tables **and** to the outbox in the same transaction. A background worker drains the outbox when there's network.

```sql
CREATE TABLE sync_queue (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type  TEXT    NOT NULL,         -- 'track', 'issue', 'photo', ...
  entity_id    INTEGER NOT NULL,         -- FK to the domain row
  operation    TEXT    NOT NULL,         -- 'create' | 'update' | 'delete'
  client_id    TEXT    NOT NULL UNIQUE,  -- UUID or composite, for backend idempotency
  status       TEXT    NOT NULL DEFAULT 'pending',   -- pending|syncing|synced|dead
  attempts     INTEGER NOT NULL DEFAULT 0,
  last_error   TEXT,
  payload      TEXT,                     -- optional JSON snapshot
  created_at   INTEGER NOT NULL,
  synced_at    INTEGER,
  remote_id    INTEGER                   -- backend-assigned id
);

CREATE INDEX idx_sync_queue_status ON sync_queue(status);
```

Rules:

- `client_id` is generated on the client and travels with the payload. The backend indexes on it and returns `200 OK` with the existing row on duplicates.
- `status` transitions: `pending → syncing → synced` on success, `syncing → pending` on retryable failure, `syncing → dead` only after an unrecoverable 4xx the user must resolve.
- `entity_id UNIQUE` is **only** appropriate when one entity has at most one pending op at a time; otherwise use `(entity_type, entity_id, operation)` as the uniqueness key.

### 2.2 Connectivity as a reactive signal

Wrap `connectivity_plus` in a service with both a snapshot getter and a listenable:

```dart
class NetworkHelper extends GetxService {
  final isConnected = ValueNotifier<bool>(false);
  final status = ValueNotifier<NetworkStatus>(NetworkStatus.checking);

  StreamSubscription? _sub;
  Timer? _heartbeat;
  bool _lastCheck = false;
  DateTime _lastCheckAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<NetworkHelper> init() async {
    _sub = Connectivity().onConnectivityChanged.listen(_onChange);
    if (!kIsWeb) _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) => _probe());
    await _onChange(await Connectivity().checkConnectivity());
    return this;
  }

  Future<bool> _probe() async {
    // cache 3s to debounce callers
    if (DateTime.now().difference(_lastCheckAt).inSeconds < 3) return _lastCheck;
    try {
      final res = await http.head(Uri.parse('https://example.com/ping'))
          .timeout(const Duration(seconds: 4));
      _lastCheck = res.statusCode < 500;
    } catch (_) {
      _lastCheck = false;
    }
    _lastCheckAt = DateTime.now();
    isConnected.value = _lastCheck;
    return _lastCheck;
  }

  @override
  void onClose() { _sub?.cancel(); _heartbeat?.cancel(); super.onClose(); }
}
```

On web, always report `true` — the browser handles it. On mobile, a 15 s HEAD heartbeat detects captive portals that return a DNS-resolvable but useless connection.

### 2.3 The SyncService

```dart
class SyncService extends GetxService {
  final pendingCount = 0.obs;
  final isSyncing = false.obs;
  final lastError = ''.obs;

  Timer? _scanTimer;

  Future<SyncService> init() async {
    AppDI.network.isConnected.addListener(_onConnectivity);
    _scanTimer = Timer.periodic(const Duration(minutes: 2), (_) => _drain());
    unawaited(_drain());
    return this;
  }

  void _onConnectivity() {
    if (AppDI.network.isConnected.value) unawaited(_drain());
  }

  Future<void> _drain() async {
    if (isSyncing.value || !AppDI.network.isConnected.value) return;
    isSyncing.value = true;
    try {
      final items = await _outbox.nextPending(limit: 5);
      for (final item in items) {
        await _processOne(item);
        if (!AppDI.network.isConnected.value) break;   // bail if we lost net mid-drain
      }
      pendingCount.value = await _outbox.countPending();
    } finally {
      isSyncing.value = false;
    }
  }

  Future<void> _processOne(SyncJob job) async {
    await _outbox.markSyncing(job.id);
    try {
      final remoteId = await _remote.send(job);
      await _outbox.markSynced(job.id, remoteId: remoteId);
      lastError.value = '';
    } on UnrecoverableApiException catch (e) {
      await _outbox.markDead(job.id, reason: e.toString());
      lastError.value = e.toString();
    } catch (e) {
      await _outbox.markPending(job.id, error: e.toString());
      lastError.value = e.toString();
    }
  }
}
```

Design notes:

- **Batch size 5** per drain: keeps the backend from being hammered after a long offline stretch.
- **No exponential backoff by default** for field apps: when the user regains signal they expect fast sync, not a retry curve. Use backoff only if the backend is the bottleneck.
- **`UnrecoverableApiException`** (4xx that the retry cannot fix: 400, 401, 403, 409, 422) moves the job to `dead`; the UI surfaces it to the user. Retryable failures (network, 5xx, 408, 429) keep it `pending`.
- **Bail mid-drain on connectivity loss**: prevents a half-processed batch from emitting confusing errors.

### 2.4 Reactive offline-first repositories

Readers never await the network. Expose local data as a `Stream` so the UI rebuilds as soon as the local write lands — the sync to the backend is invisible to the user.

```dart
class InspectionRepository implements IInspectionRepository {
  final AppDatabase _db;
  final OutboxQueue _outbox;
  final NetworkHelper _network;

  /// Writes locally, enqueues, and fires off a best-effort sync if online.
  /// Returns immediately — never blocks the UI on the network.
  Future<Either<Failure, InspectionEntity>> create(InspectionEntity e) async {
    try {
      final clientId = const Uuid().v4();
      final stamped = e.copyWith(clientId: clientId, updatedAt: DateTime.now());
      await _db.inspections.insert(stamped.toRow());
      await _outbox.enqueue(SyncJob.create('inspection', clientId, stamped.toJson()));
      if (_network.isConnected.value) unawaited(Get.find<SyncService>()._drain());
      return Right(stamped);
    } catch (err) {
      return Left(CacheFailure(err.toString()));
    }
  }

  /// Reads from the local DB only — `Stream` so the UI updates on every write.
  Stream<Either<Failure, List<InspectionEntity>>> watchAll() {
    return _db.inspections.watchAll().map((rows) {
      try {
        return Right<Failure, List<InspectionEntity>>(
          rows.map(InspectionEntity.fromRow).toList(),
        );
      } catch (err) {
        return Left<Failure, List<InspectionEntity>>(CacheFailure(err.toString()));
      }
    });
  }
}
```

Key rules:

- `clientId` is generated on the client and travels with the payload. The backend indexes on it. Replaying the same `clientId` must be a no-op.
- The `create` method never awaits a network call — it returns as soon as the local row and the outbox row are committed.
- `watchAll()` returns a `Stream` backed by the local DB (Drift's `.watch()` or a manual `StreamController` over `sqflite`). The UI reacts to local writes; the sync service reacts to outbox changes independently.

### 2.5 Retry philosophy

Two valid approaches. Pick one per app and document the choice:

| Strategy | When to use | Implementation |
|---|---|---|
| **Retry forever, no backoff** | Field apps with long offline stretches | On failure, `status → pending`, `attempts++`. Next drain cycle retries. User sees a pending counter |
| **Bounded retries then `dead`** | Generic CRUD apps with normal connectivity | After N (typically 3) attempts, mark row as `dead` / `conflict`. Surface it to the user for manual resolution |

```dart
// Bounded-retry variant
Future<void> _processOne(SyncJob job) async {
  if (job.attempts >= 3) {
    await _outbox.markDead(job.id, reason: 'Exceeded max retries');
    await _entities.markConflict(job.entityType, job.entityId);
    return;
  }
  await _outbox.markSyncing(job.id, attempt: job.attempts + 1);
  try {
    final remoteId = await _remote.send(job);
    await _outbox.markSynced(job.id, remoteId: remoteId);
  } on UnrecoverableApiException catch (e) {
    await _outbox.markDead(job.id, reason: e.toString());
  } catch (e) {
    await _outbox.markPending(job.id, error: e.toString());
  }
}
```

`UnrecoverableApiException` wraps 4xx that retrying cannot fix (400, 401, 403, 409, 422). Retryable failures (network, 5xx, 408, 429) stay `pending`.

### 2.6 Chunked uploads

For large payloads (tracks with thousands of points, multi-photo forms), split at the domain level:

```dart
Future<int> syncTrack(TrackEntity t) async {
  // Phase 1: header → remote_id
  final remoteId = await _http.post('/tracks', body: t.header()).idOrThrow;

  // Phase 2: points in chunks of 500, 150ms between chunks
  for (final chunk in t.points.chunked(500)) {
    await _http.post('/tracks/$remoteId/points', body: {'points': chunk});
    await Future.delayed(const Duration(milliseconds: 150));
  }
  return remoteId;
}
```

Chunking lets the backend commit progressively and keeps timeouts manageable. Use `multipart/form-data` for photo batches; let the HTTP client stream from disk with `http.MultipartFile.fromPath` rather than holding bytes in memory.

### 2.7 Conflict resolution

When an offline client and the backend (or a second device) both modify the same entity, someone has to lose. Pick a strategy per entity type and **document the decision in the codebase**:

| Strategy | When to use | Implementation |
|---|---|---|
| **Last-write-wins** | Logs, append-only data, low-stakes fields | Compare `updated_at`; newer wins |
| **Server wins** | Catalogues, reference data, anything curated centrally | On 409, discard local change and refetch |
| **Client wins** | Field notes where the operator's observation is authoritative | Send with `If-Match: *` / force-overwrite |
| **Manual resolution** | High-value records where no automatic choice is safe | Mark entity `status='conflict'`, surface a UI for the user |

Manual resolution pattern:

```dart
Future<void> resolveConflict(String clientId) async {
  final local = await _local.byClientId(clientId);
  final remote = await _remote.byClientId(clientId);

  final choice = await Get.dialog<ConflictChoice>(
    ConflictResolutionDialog(local: local, remote: remote),
    barrierDismissible: false,
  );

  switch (choice) {
    case ConflictChoice.keepLocal:
      await _outbox.enqueue(SyncJob.forceUpdate(local));
    case ConflictChoice.keepRemote:
      await _local.overwrite(clientId, remote);
      await _outbox.removeFor(clientId);
    case ConflictChoice.merge:
      final merged = _mergeStrategy.merge(local, remote);
      await _local.overwrite(clientId, merged);
      await _outbox.enqueue(SyncJob.forceUpdate(merged));
    case null:
      return; // user dismissed
  }
  await _entities.clearConflict(clientId);
}
```

Never auto-resolve conflicts silently on high-value data — users lose trust fast when their work disappears without explanation. For lower-value data, surface the choice in a non-blocking badge that the user can ignore if they do not care.

### 2.8 Sync status UI

Offline-first apps must make sync state **visible at all times**. Field operators need to know whether their work is safely on the backend or still on the phone. A persistent badge in the app bar is the cheapest way:

```dart
class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final net = Get.find<NetworkHelper>();
    final sync = Get.find<SyncService>();

    return ValueListenableBuilder<bool>(
      valueListenable: net.isConnected,
      builder: (_, online, __) => Obx(() {
        if (!online) {
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
            label: Text('Sincronizando…'),
          );
        }
        if (sync.pendingCount.value > 0) {
          return Chip(
            avatar: const Icon(Icons.sync_problem, size: 16),
            label: Text('${sync.pendingCount.value} pendientes'),
            backgroundColor: Colors.yellow.shade100,
          );
        }
        return const Chip(
          avatar: Icon(Icons.cloud_done, size: 16, color: Colors.green),
          label: Text('Sincronizado'),
        );
      }),
    );
  }
}
```

Rules:

- Badge states must be mutually exclusive: **offline**, **syncing**, **pending > 0**, **all synced**. No ambiguous "?" state.
- Tapping the badge should open a detail screen listing pending items and any conflicts — never leave the user without a way to inspect or retry.
- Do not show a badge only inside one screen — place it globally (app bar or permanent overlay) so the user sees it in any workflow.

---

## 3. Buffered Writes (Hot Tables)

For high-frequency sensor data (GPS at 1 Hz, accelerometer at 50 Hz), inserting one row per event is I/O suicide. Buffer in memory and flush in batches.

```dart
class PointsRepository {
  static const _bufferSize = 50;
  static const _flushInterval = Duration(seconds: 30);

  final List<TrackPoint> _buffer = [];
  Timer? _flushTimer;

  Future<void> addPoint(TrackPoint p) async {
    _buffer.add(p);
    if (_buffer.length >= _bufferSize) await flush();
  }

  Future<void> flush() async {
    if (_buffer.isEmpty) return;
    final toWrite = List.of(_buffer);
    _buffer.clear();
    await _db.transaction((tx) async {
      final batch = tx.batch();
      for (final p in toWrite) {
        batch.insert('track_points', p.toJson());
      }
      await batch.commit(noResult: true);
    });
  }

  void startAutoFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => unawaited(flush()));
  }
}
```

Tradeoff: on a crash you lose up to `_bufferSize` events (30 s at 1 Hz). That is acceptable for field GPS. For financial/safety-critical writes, set `_bufferSize = 1` and eat the I/O.

---

## 4. State Recovery After Crash

Persist a single-row table that reflects the current long-running state. On app start, read it and rebuild the session.

```sql
CREATE TABLE job_state (
  id             INTEGER PRIMARY KEY CHECK (id = 1),   -- singleton row
  state          TEXT NOT NULL DEFAULT 'idle',
  entity_id      INTEGER,
  started_at     INTEGER,
  last_save_at   INTEGER,
  metric_1       REAL DEFAULT 0.0
);
```

```dart
Future<void> initialize() async {
  await _state.open();
  final snapshot = await _state.load();
  if (snapshot == null || snapshot.state == 'idle') return;

  final gap = DateTime.now().millisecondsSinceEpoch - snapshot.lastSaveAt;
  if (gap > const Duration(minutes: 5).inMilliseconds) {
    _notifier.warn('Session recovered after unexpected shutdown');
  }
  await _resumeFrom(snapshot);
}
```

Rules:

- Singleton row (`CHECK (id = 1)`) — avoids accidental duplicates, enables direct UPDATE-or-INSERT.
- `last_save_at` on every mutation: enables crash detection via time gap.
- Never store runtime-only data (timers, subscriptions) in this table — only what you need to resume.

---

## 5. Adaptive Power Management

Streaming GPS is the single largest battery cost in a field app. Adapt sampling to context.

```dart
class AdaptiveConfig {
  static TrackingConfig forContext({
    required double speedMps,
    required bool isBackground,
    int? batteryPercent,
  }) {
    // base tier by speed
    var (interval, distance) = switch (speedMps) {
      < 1  => (const Duration(seconds: 15), 30),   // stationary
      < 5  => (const Duration(seconds: 7),  15),   // walking
      _    => (const Duration(seconds: 3),  5),    // vehicle
    };

    // background always more conservative
    if (isBackground) {
      interval *= 2;
      distance *= 2;
    }

    // battery override
    final b = batteryPercent ?? 100;
    if (b < 15) { interval *= 3; distance *= 3; }
    else if (b < 30) { interval *= 2; distance *= 2; }

    return TrackingConfig(
      intervalDuration: interval,
      distanceFilter: distance,
      accuracy: b < 15 ? LocationAccuracy.medium : LocationAccuracy.high,
    );
  }
}
```

Re-evaluate on every few points or whenever the app lifecycle changes. Do not re-init the stream on every tick — only when the new config differs meaningfully from the current one (e.g., interval changed by >50%).

---

## 6. SQLite Concurrency for Multi-Isolate Apps

When the main isolate and a background isolate both write to the same DB:

- Enable WAL mode on open: `PRAGMA journal_mode = WAL;`
- Each isolate opens its **own** `Database` handle. Do not share across isolates — `sqflite`'s handles are not isolate-safe.
- Prefer short transactions. Long transactions in one isolate block writes from the other.
- Use `CONFLICT_REPLACE` / `CONFLICT_IGNORE` strategically to avoid unnecessary read-before-write races.

```dart
Future<Database> openIsolateDb() async {
  final path = join(await getDatabasesPath(), 'app.db');
  return openDatabase(
    path,
    onConfigure: (db) async {
      await db.execute('PRAGMA journal_mode = WAL;');
      await db.execute('PRAGMA synchronous = NORMAL;');  // WAL-safe, ~2x throughput
      await db.execute('PRAGMA foreign_keys = ON;');
    },
  );
}
```

---

## 7. Testing Background & Sync Code

Isolates and platform channels are hostile to unit tests. Test in layers:

| Layer | Test type | How |
|---|---|---|
| SyncService logic | Unit | Inject a fake `OutboxQueue` and `RemoteProvider` (mocktail); assert state transitions |
| OutboxQueue SQL | Unit | Use `sqflite_common_ffi` in-memory DB; run real SQL |
| Background entry point | Manual + integration | Cannot unit-test the isolate itself; test the pure functions it calls |
| Lifecycle transitions | Widget test | Use `WidgetTester.binding.handleAppLifecycleStateChanged(...)` |
| End-to-end | Integration | `integration_test` on a real device with the service running |

Never skip the OutboxQueue SQL tests with mocks — the bugs always live in the SQL.

---

## 8. Common Pitfalls

- **Forgetting `DartPluginRegistrant.ensureInitialized()`** in the background entry point → plugins silently return null.
- **Sharing a SQLite handle across isolates** → database locked errors or silent data loss.
- **Awaiting `Get.find<T>()` in the background isolate** → hangs forever because the DI container lives in the main isolate.
- **Using `ACCESS_BACKGROUND_LOCATION`** when a Foreground Service would do → Play Store rejections.
- **Not calling `.cancel()` on `StreamSubscription` in `onClose()` / on stop** → GPS keeps draining battery after the user stopped.
- **Reading `kIsWeb` at the top of a service file** → fine, but never use `dart:io` in cross-platform sync code; conditional imports (`if (dart.library.io)`) are the right pattern.
- **Assuming the OS honours `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`** → it's a request, not a guarantee; on Xiaomi/Huawei/OnePlus the user must whitelist the app manually. Document this in onboarding.
- **Relying on periodic `workmanager` tasks for real-time sync** → minimum 15 min interval, and Doze can delay further. Use it only for genuinely periodic work (daily cleanup, weekly report upload).

---

## 9. Decision Checklist (before writing a new feature that touches this skill)

- [ ] What is the `client_id` for new rows? Who generates it?
- [ ] Does every user write hit local storage **before** any network call?
- [ ] Is there an outbox row for every operation that must eventually reach the backend?
- [ ] If the app is killed mid-operation, what state is on disk? Is it enough to resume?
- [ ] Does the backend idempotently accept the same `client_id` twice?
- [ ] Which conflict-resolution strategy applies (last-write-wins / server / client / manual)? Is it documented?
- [ ] On Android, does the feature need a Foreground Service? If yes, which `foregroundServiceType`?
- [ ] On iOS, is the relevant `UIBackgroundModes` entry present?
- [ ] What happens when the buffer overflows or the disk is full?
- [ ] Is `SyncStatusBadge` (or equivalent) visible from every screen the user can edit on?
- [ ] Have you surfaced `pendingCount`, `lastError` and conflicts somewhere the user can act on?

---

## Reference Files

- `references/background-platforms.md` — Android Doze whitelisting, iOS BGTaskScheduler quirks, vendor-specific battery optimisers (Xiaomi, Huawei, Samsung)
- `references/sync-conflict-resolution.md` — Last-write-wins, CRDT basics, vector clocks when two devices edit the same entity offline
- `references/outbox-migration.md` — Safely migrating an existing online-only feature onto the outbox pattern without losing in-flight data
