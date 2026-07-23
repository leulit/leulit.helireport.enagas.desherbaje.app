import '../contracts/remote_adapter.dart';
import '../contracts/sync_job.dart';
import '../contracts/syncable.dart';
import '../contracts/sync_progress.dart';
import '../pull/cancel_token.dart';
import '../type_registry.dart';

/// Mutable context that flows through every task of the per-job pipeline.
class SyncJobContext {
  final SyncJob job;
  final TypeRegistration<Syncable> registration;

  /// Cancellation flag of the drain in progress. Travels in the context so the
  /// adapter can honour it inside its own long loops; null when the caller did
  /// not supply one.
  final CancelToken? token;

  /// Sumidero de progreso para adaptadores con bucles largos (vídeo). Null
  /// cuando el llamante no pinta progreso.
  final SyncProgressCallback? onProgress;

  Syncable? entity;
  SyncOutcome<Syncable>? outcome;

  /// Outcome category after [InterpretOutcomeTask] has classified the adapter
  /// result. Null until the pipeline sets it; the engine reads [result!].
  SyncJobResult? result;

  SyncJobContext({
    required this.job,
    required this.registration,
    this.token,
    this.onProgress,
  });
}

enum SyncJobResult {
  succeeded,
  retryable,
  rejected,
  conflict,
}
