import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/app_router.dart';
import '../../core/my_getx_controller.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/sync/sync.dart';
import 'field_work_tasks.dart';
import 'sync_models.dart';

class SincronizacionController extends MyGetxController {
  SincronizacionController({
    OutboxQueue? outbox,
    SyncEngine? engine,
    Database? db,
    TypeRegistry? registry,
    ConnectivityService? connectivity,
  })  : _outbox = outbox ?? Get.find<OutboxQueue>(),
        _engine = engine ?? Get.find<SyncEngine>(),
        _db = db ?? Get.find<Database>(),
        _registry = registry ?? Get.find<TypeRegistry>(),
        _connectivity = connectivity ?? Get.find<ConnectivityService>();

  final OutboxQueue _outbox;
  final SyncEngine _engine;
  final Database _db;
  final TypeRegistry _registry;
  final ConnectivityService _connectivity;

  // ─────────────────────────────── State ───────────────────────────────

  final isOnline = true.obs;
  final isWorking = false.obs;
  final currentStep = ''.obs;
  final lastReport = Rxn<FieldReadinessReport>();
  final lastDrainSummary = Rxn<DrainSummary>();
  final lastError = Rxn<String>();

  final pendingByEntity = <PendingByEntity>[].obs;
  final downloadable = <DownloadableEntity>[].obs;
  final conflicts = <ConflictRow>[].obs;
  final rejectedJobs = <SyncJob>[].obs;

  CancelToken? _activeToken;

  // ─────────────────────────────── Lifecycle ───────────────────────────

  @override
  void myOnInit() {
    isOnline.value = _connectivity.isConnected;
    onTypedAction(
      SyncActions.connectionRestored,
      (_) => isOnline.value = true,
      debugLabel: 'Sync.connRestored',
    );
    onTypedAction(
      SyncActions.connectionLost,
      (_) => isOnline.value = false,
      debugLabel: 'Sync.connLost',
    );
    onTypedAction(
      SyncActions.entityQueued,
      (_) => refreshAll(),
      debugLabel: 'Sync.entityQueued',
    );
    onTypedAction(
      SyncActions.entitySynced,
      (_) => refreshAll(),
      debugLabel: 'Sync.entitySynced',
    );
    onTypedAction(
      SyncActions.entityRejected,
      (_) => refreshAll(),
      debugLabel: 'Sync.entityRejected',
    );
    onTypedAction(
      SyncActions.entityConflict,
      (_) => refreshAll(),
      debugLabel: 'Sync.entityConflict',
    );
    onTypedAction(
      SyncActions.cloudPullCompleted,
      (_) => refreshAll(),
      debugLabel: 'Sync.cloudPullCompleted',
    );
    refreshAll();
  }

  // ─────────────────────────────── Refresh ─────────────────────────────

  Future<void> refreshAll() async {
    await Future.wait([
      _refreshPending(),
      _refreshDownloadable(),
      _refreshConflicts(),
      _refreshRejected(),
    ]);
  }

  Future<void> _refreshPending() async {
    final entityTypes = _registry.registrations.map((r) => r.entityType).toList();
    final rows = <PendingByEntity>[];
    for (final type in entityTypes) {
      final pending = await _outbox.countPending(entityType: type);
      final rejected = await _outbox.countRejected(entityType: type);
      rows.add(PendingByEntity(
        entityType: type,
        pending: pending,
        rejected: rejected,
      ));
    }
    pendingByEntity.assignAll(rows);
  }

  Future<void> _refreshDownloadable() async {
    final pulleable = OfflineModule.pulleableEntityTypes.toList();
    final rows = <DownloadableEntity>[];
    for (final type in pulleable) {
      final result = await _db.query(
        OfflineDatabase.pullStateTable,
        where: 'entity_type = ?',
        whereArgs: [type],
        limit: 1,
      );
      if (result.isEmpty) {
        rows.add(DownloadableEntity(entityType: type));
        continue;
      }
      final row = result.first;
      rows.add(DownloadableEntity(
        entityType: type,
        lastPulledAt: row['last_pulled_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['last_pulled_at']! as int),
        lastStatus: row['last_status'] as String?,
        lastError: row['last_error'] as String?,
      ));
    }
    downloadable.assignAll(rows);
  }

  Future<void> _refreshConflicts() async {
    final rows = await _db.query(
      OfflineDatabase.syncConflictsTable,
      orderBy: 'detected_at DESC',
    );
    conflicts.assignAll(rows.map((r) => ConflictRow(
          id: r['id']! as int,
          entityType: r['entity_type']! as String,
          clientId: r['client_id']! as String,
          localJson: jsonDecode(r['local_json']! as String) as Map<String, dynamic>,
          remoteJson: jsonDecode(r['remote_json']! as String) as Map<String, dynamic>,
          detectedAt:
              DateTime.fromMillisecondsSinceEpoch(r['detected_at']! as int),
        )));
  }

  Future<void> _refreshRejected() async {
    rejectedJobs.assignAll(await _outbox.rejectedJobs());
  }

  // ─────────────────────────────── Actions ─────────────────────────────

  Future<void> prepararTrabajoCampo() async {
    if (isWorking.value) return;
    isWorking.value = true;
    currentStep.value = 'Preparando…';
    lastError.value = null;
    _activeToken = CancelToken();
    final ctx = FieldWorkContext()..cancelToken = _activeToken;

    final pipeline = TaskPipeline<FieldWorkContext>()
      ..addTask(CheckOnlineTask())
      ..addTask(DrainOutboxTask())
      ..addTask(PullAllPulleableTask());

    try {
      currentStep.value = 'Comprobando conexión…';
      final result = await pipeline.run(DataPipeline.of(ctx));
      pipeline.dispose();
      result.fold(
        onSuccess: (_) {},
        onFailure: (err, _) => lastError.value = err.toString(),
      );
    } finally {
      lastReport.value = FieldReadinessReport(
        pendingPushed: ctx.pendingPushed,
        pendingFailed: ctx.pendingFailed,
        pulledOk: ctx.pulledOk,
        conflictsFound: ctx.conflictsFound,
        errors: List.unmodifiable(ctx.errors),
        cancelled: ctx.cancelled,
        authExpired: ctx.authExpired,
      );
      _activeToken = null;
      isWorking.value = false;
      currentStep.value = '';
      await refreshAll();
    }
  }

  Future<void> subirTodo() async {
    if (isWorking.value) return;
    isWorking.value = true;
    currentStep.value = 'Subiendo todo…';
    try {
      final summary = await _engine.drain();
      lastDrainSummary.value = summary;
    } catch (e) {
      lastError.value = e.toString();
    } finally {
      isWorking.value = false;
      currentStep.value = '';
      await refreshAll();
    }
  }

  Future<void> subirEntidad(String entityType) async {
    if (isWorking.value) return;
    isWorking.value = true;
    currentStep.value = 'Subiendo $entityType…';
    try {
      final summary = await _engine.drain(entityType: entityType);
      lastDrainSummary.value = summary;
    } catch (e) {
      lastError.value = e.toString();
    } finally {
      isWorking.value = false;
      currentStep.value = '';
      await refreshAll();
    }
  }

  Future<void> descargarEntidad(String entityType) async {
    if (isWorking.value) return;
    isWorking.value = true;
    currentStep.value = 'Descargando $entityType…';
    _activeToken = CancelToken();
    try {
      await OfflineModule.runPull(entityType, token: _activeToken);
    } catch (e) {
      lastError.value = e.toString();
    } finally {
      _activeToken = null;
      isWorking.value = false;
      currentStep.value = '';
      await refreshAll();
    }
  }

  void cancelar() {
    _activeToken?.cancel();
  }

  Future<void> reintentarRechazado(int jobId) async {
    await _outbox.retryRejected(jobId);
    await refreshAll();
  }

  Future<void> descartarRechazado(int jobId) async {
    await _outbox.discardJob(jobId);
    await refreshAll();
  }

  Future<void> resolverConflicto({
    required ConflictRow conflict,
    required ConflictResolutionChoice choice,
  }) async {
    final registration = _registry.lookup(conflict.entityType);
    if (registration == null) return;
    if (choice == ConflictResolutionChoice.keepServer) {
      final remoteEntity = registration.fromJson(conflict.remoteJson);
      await registration.store.upsert(remoteEntity);
      await registration.store.markSynced(
        clientId: remoteEntity.clientId,
        remoteId: remoteEntity.remoteId,
      );
      await _outbox.removeForEntity(
        entityType: conflict.entityType,
        clientId: conflict.clientId,
      );
    } else {
      await _outbox.enqueue(
        entityType: conflict.entityType,
        clientId: conflict.clientId,
        operation: SyncOperation.update,
      );
    }
    await _db.delete(
      OfflineDatabase.syncConflictsTable,
      where: 'id = ?',
      whereArgs: [conflict.id],
    );
    await refreshAll();
  }

  ({
    Map<String, String> local,
    Map<String, String> remote,
    Set<String> diffKeys,
  }) formatConflict(ConflictRow conflict) {
    final registration = _registry.lookup(conflict.entityType);
    if (registration == null || registration.formatForDisplay == null) {
      final local = conflict.localJson
          .map((k, v) => MapEntry(k, v?.toString() ?? '—'));
      final remote = conflict.remoteJson
          .map((k, v) => MapEntry(k, v?.toString() ?? '—'));
      final keys = <String>{...local.keys, ...remote.keys}
          .where((k) => local[k] != remote[k])
          .toSet();
      return (local: local, remote: remote, diffKeys: keys);
    }
    final localEntity = registration.fromJson(conflict.localJson);
    final remoteEntity = registration.fromJson(conflict.remoteJson);
    final formatter = registration.formatForDisplay!;
    final local = formatter(localEntity);
    final remote = formatter(remoteEntity);
    final keys = <String>{...local.keys, ...remote.keys}
        .where((k) => local[k] != remote[k])
        .toSet();
    return (local: local, remote: remote, diffKeys: keys);
  }

  void volver() {
    if (isWorking.value) return;
    Get.back<void>();
  }

  void irASegmentos() {
    if (isWorking.value) return;
    Get.offAllNamed(AppRoutes.segmentos);
  }

  Color colorForStatus(BuildContext context) {
    if (lastError.value != null) return Colors.red.shade700;
    final report = lastReport.value;
    if (report == null) return Theme.of(context).colorScheme.primary;
    if (report.authExpired) return Colors.red.shade700;
    if (!report.isReadyForField) return Colors.orange.shade700;
    return Colors.green.shade700;
  }
}
