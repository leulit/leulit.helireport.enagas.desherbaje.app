import '../../core/sync/sync.dart';

/// Aggregated outbox state for a single entity type, used by the sync page
/// "Pendientes de subir" section.
class PendingByEntity {
  final String entityType;
  final int pending;
  final int rejected;

  const PendingByEntity({
    required this.entityType,
    required this.pending,
    required this.rejected,
  });

  bool get hasAnything => pending > 0 || rejected > 0;
}

/// Snapshot of the pull state for a single pulleable entity type, used by
/// the sync page "Datos descargables" section.
class DownloadableEntity {
  final String entityType;
  final DateTime? lastPulledAt;
  final String? lastStatus;
  final String? lastError;

  const DownloadableEntity({
    required this.entityType,
    this.lastPulledAt,
    this.lastStatus,
    this.lastError,
  });
}

/// A row in the `sync_conflicts` table, ready to be rendered as a diff in
/// the "Conflictos de descarga" section.
class ConflictRow {
  final int id;
  final String entityType;
  final String clientId;
  final Map<String, dynamic> localJson;
  final Map<String, dynamic> remoteJson;
  final DateTime detectedAt;

  const ConflictRow({
    required this.id,
    required this.entityType,
    required this.clientId,
    required this.localJson,
    required this.remoteJson,
    required this.detectedAt,
  });
}

/// Outcome of `prepararTrabajoCampo`: counts and a flag of whether the
/// operator can safely go to the field.
class FieldReadinessReport {
  final int pendingPushed;
  final int pendingFailed;
  final int pulledOk;
  final int conflictsFound;
  final List<String> errors;
  final bool cancelled;
  final bool authExpired;

  const FieldReadinessReport({
    required this.pendingPushed,
    required this.pendingFailed,
    required this.pulledOk,
    required this.conflictsFound,
    required this.errors,
    required this.cancelled,
    required this.authExpired,
  });

  bool get isReadyForField =>
      !cancelled && !authExpired && conflictsFound == 0 && pendingFailed == 0;
}

/// Decision made by the operator when resolving a single conflict.
enum ConflictResolutionChoice { keepLocal, keepServer }

/// Internal pipeline context for "Preparar trabajo de campo".
class FieldWorkContext {
  final List<String> errors = [];
  int pendingPushed = 0;
  int pendingFailed = 0;
  int pulledOk = 0;
  int conflictsFound = 0;
  bool cancelled = false;
  bool authExpired = false;

  CancelToken? cancelToken;
}
