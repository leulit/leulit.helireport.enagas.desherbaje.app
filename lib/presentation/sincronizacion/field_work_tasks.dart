import 'package:get/get.dart';
import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

import '../../core/services/connectivity_service.dart';
import '../../core/sync/sync.dart';
import 'sync_models.dart';

class CheckOnlineTask extends PipelineTask<FieldWorkContext> {
  @override
  String get name => 'CheckOnline';

  @override
  bool get isBlocking => true;

  @override
  Future<DataPipeline<FieldWorkContext>> execute(
    DataPipeline<FieldWorkContext> data,
  ) async {
    final ctx = data.output;
    final connectivity = Get.find<ConnectivityService>();
    if (!connectivity.isConnected) {
      ctx.errors.add('No hay conexión a internet.');
      return DataPipeline.error(
        input: ctx,
        error: StateError('No hay conexión a internet.'),
      );
    }
    return DataPipeline.success(input: ctx, output: ctx);
  }
}

class DrainOutboxTask extends PipelineTask<FieldWorkContext> {
  @override
  String get name => 'DrainOutbox';

  @override
  bool get isBlocking => false;

  @override
  Future<DataPipeline<FieldWorkContext>> execute(
    DataPipeline<FieldWorkContext> data,
  ) async {
    final ctx = data.output;
    if (ctx.cancelToken?.isCancelled ?? false) {
      ctx.cancelled = true;
      return DataPipeline.success(input: ctx, output: ctx);
    }
    final engine = Get.find<SyncEngine>();
    final summary = await engine.drain();
    ctx.pendingPushed = summary.succeeded;
    ctx.pendingFailed = summary.retryable + summary.rejected;
    if (summary.authExpired) {
      ctx.authExpired = true;
      return DataPipeline.error(
        input: ctx,
        error: StateError('La sesión ha expirado durante la subida.'),
      );
    }
    return DataPipeline.success(input: ctx, output: ctx);
  }
}

class PullAllPulleableTask extends PipelineTask<FieldWorkContext> {
  @override
  String get name => 'PullAllPulleable';

  @override
  bool get isBlocking => false;

  @override
  Future<DataPipeline<FieldWorkContext>> execute(
    DataPipeline<FieldWorkContext> data,
  ) async {
    final ctx = data.output;
    if (ctx.cancelToken?.isCancelled ?? false) {
      ctx.cancelled = true;
      return DataPipeline.success(input: ctx, output: ctx);
    }
    final entityTypes = OfflineModule.pulleableEntityTypes.toList();
    for (final type in entityTypes) {
      if (ctx.cancelToken?.isCancelled ?? false) {
        ctx.cancelled = true;
        break;
      }
      try {
        final summary = await OfflineModule.runPull(
          type,
          token: ctx.cancelToken,
        );
        if (summary == null) continue;
        if (summary.authExpired) {
          ctx.authExpired = true;
          return DataPipeline.error(
            input: ctx,
            error: StateError('La sesión ha expirado durante la descarga.'),
          );
        }
        ctx.pulledOk += summary.upserted;
        ctx.conflictsFound += summary.conflicts;
        if (summary.cancelled) {
          ctx.cancelled = true;
          break;
        }
      } catch (e) {
        ctx.errors.add('Error descargando "$type": $e');
      }
    }
    return DataPipeline.success(input: ctx, output: ctx);
  }
}
