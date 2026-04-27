import 'package:uuid/uuid.dart';

import '../../core/sync/contracts/syncable.dart';

/// One GPS sample. Plain data — no `Syncable` because points are never
/// synced individually; they're aggregated into a [PositionBatchEntity].
class PositionPoint {
  final DateTime capturedAt;
  final double lat;
  final double lng;
  final double? accuracyMeters;
  final double? altitudeMeters;
  final double? speedMps;

  const PositionPoint({
    required this.capturedAt,
    required this.lat,
    required this.lng,
    this.accuracyMeters,
    this.altitudeMeters,
    this.speedMps,
  });

  Map<String, dynamic> toJson() => {
        'captured_at': capturedAt.toIso8601String(),
        'lat': lat,
        'lng': lng,
        if (accuracyMeters != null) 'accuracy_m': accuracyMeters,
        if (altitudeMeters != null) 'altitude_m': altitudeMeters,
        if (speedMps != null) 'speed_mps': speedMps,
      };

  factory PositionPoint.fromJson(Map<String, dynamic> json) => PositionPoint(
        capturedAt: DateTime.parse(json['captured_at'] as String),
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        accuracyMeters: (json['accuracy_m'] as num?)?.toDouble(),
        altitudeMeters: (json['altitude_m'] as num?)?.toDouble(),
        speedMps: (json['speed_mps'] as num?)?.toDouble(),
      );
}

/// A batch of up to ~500 GPS points. The unit of synchronisation: one
/// outbox job pushes one batch with all its points in a single HTTP request
/// to `POST /positions/batch`.
class PositionBatchEntity implements Syncable {
  PositionBatchEntity({
    required this.operadorId,
    required this.points,
    required this.startedAt,
    required this.endedAt,
    String? clientId,
    this.id,
    DateTime? updatedAt,
  })  : _clientId = clientId ?? const Uuid().v4(),
        _updatedAt = updatedAt ?? DateTime.now();

  final String _clientId;
  final DateTime _updatedAt;

  int? id;
  int operadorId;
  List<PositionPoint> points;
  DateTime startedAt;
  DateTime endedAt;

  @override
  String get clientId => _clientId;

  @override
  String? get remoteId => id?.toString();

  @override
  DateTime get updatedAt => _updatedAt;

  @override
  Map<String, dynamic> toJson() => {
        'batch_client_id': clientId,
        if (id != null) 'remote_id': id,
        'operador_id': operadorId,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'points': points.map((p) => p.toJson()).toList(),
      };

  factory PositionBatchEntity.fromJson(Map<String, dynamic> json) =>
      PositionBatchEntity(
        clientId: json['batch_client_id'] as String?,
        id: json['remote_id'] as int?,
        operadorId: (json['operador_id'] as num?)?.toInt() ?? 0,
        startedAt: DateTime.parse(json['started_at'] as String),
        endedAt: DateTime.parse(json['ended_at'] as String),
        points: ((json['points'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => PositionPoint.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionBatchEntity && other._clientId == _clientId;

  @override
  int get hashCode => _clientId.hashCode;
}
