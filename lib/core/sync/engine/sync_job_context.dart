import '../contracts/remote_adapter.dart';
import '../contracts/sync_job.dart';
import '../contracts/syncable.dart';
import '../type_registry.dart';

/// Mutable context that flows through every task of the per-job pipeline.
class SyncJobContext {
  final SyncJob job;
  final TypeRegistration<Syncable> registration;

  Syncable? entity;
  SyncOutcome<Syncable>? outcome;

  /// Outcome category after [InterpretOutcomeTask] has classified the adapter
  /// result. Null until the pipeline sets it; the engine reads [result!].
  SyncJobResult? result;

  SyncJobContext({required this.job, required this.registration});
}

enum SyncJobResult {
  succeeded,
  retryable,
  rejected,
  conflict,
}
