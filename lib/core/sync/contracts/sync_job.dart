enum SyncOperation {
  create,
  update,
  delete;

  String get wireName => name;

  static SyncOperation fromWire(String value) =>
      SyncOperation.values.firstWhere((op) => op.wireName == value);
}

enum SyncStatus {
  pending,
  syncing,
  synced,
  rejected;

  String get wireName => name;

  static SyncStatus fromWire(String value) =>
      SyncStatus.values.firstWhere((s) => s.wireName == value);
}

class SyncJob {
  final int id;
  final String entityType;
  final String clientId;
  final SyncOperation operation;
  final SyncStatus status;
  final int attempts;
  final String? lastError;
  final int? statusCode;
  final DateTime createdAt;
  final DateTime? syncedAt;
  final String? remoteId;

  const SyncJob({
    required this.id,
    required this.entityType,
    required this.clientId,
    required this.operation,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.lastError,
    this.statusCode,
    this.syncedAt,
    this.remoteId,
  });

  factory SyncJob.fromRow(Map<String, Object?> row) => SyncJob(
        id: row['id']! as int,
        entityType: row['entity_type']! as String,
        clientId: row['client_id']! as String,
        operation: SyncOperation.fromWire(row['operation']! as String),
        status: SyncStatus.fromWire(row['status']! as String),
        attempts: row['attempts']! as int,
        lastError: row['last_error'] as String?,
        statusCode: row['status_code'] as int?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
        syncedAt: row['synced_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['synced_at']! as int),
        remoteId: row['remote_id'] as String?,
      );
}
