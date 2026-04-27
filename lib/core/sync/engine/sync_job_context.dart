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

  /// Outcome category after [InterpretSyncOutcomeTask] has classified the
  /// adapter result.
  SyncJobResult result = SyncJobResult.pending;

  SyncJobContext({required this.job, required this.registration});
}

enum SyncJobResult {
  pending,
  succeeded,
  retryable,
  rejected,
  conflict,
}
