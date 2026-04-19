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
  dead;

  String get wireName => name;

  static SyncStatus fromWire(String value) =>
      SyncStatus.values.firstWhere((s) => s.wireName == value);
}

class SyncJob {
  final int id;
  final String entityType;
  final String entityId;
  final SyncOperation operation;
  final SyncStatus status;
  final int attempts;
  final String? lastError;
  final String? payload;
  final DateTime createdAt;
  final DateTime? syncedAt;
  final String? remoteId;

  const SyncJob({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.lastError,
    this.payload,
    this.syncedAt,
    this.remoteId,
  });

  factory SyncJob.fromRow(Map<String, Object?> row) => SyncJob(
        id: row['id']! as int,
        entityType: row['entity_type']! as String,
        entityId: row['entity_id']! as String,
        operation: SyncOperation.fromWire(row['operation']! as String),
        status: SyncStatus.fromWire(row['status']! as String),
        attempts: row['attempts']! as int,
        lastError: row['last_error'] as String?,
        payload: row['payload'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
        syncedAt: row['synced_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['synced_at']! as int),
        remoteId: row['remote_id'] as String?,
      );

  SyncJob copyWith({
    SyncStatus? status,
    int? attempts,
    String? lastError,
    DateTime? syncedAt,
    String? remoteId,
  }) =>
      SyncJob(
        id: id,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        status: status ?? this.status,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
        payload: payload,
        createdAt: createdAt,
        syncedAt: syncedAt ?? this.syncedAt,
        remoteId: remoteId ?? this.remoteId,
      );
}
