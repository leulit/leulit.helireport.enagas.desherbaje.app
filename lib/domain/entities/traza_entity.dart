import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/sync/contracts/syncable.dart';

/// One GPS sample within a [TrazaEntity]. Plain data — no `Syncable` because
/// points are never synced individually, only as part of their traza.
class TrazaPunto {
  final DateTime capturedAt;
  final double lat;
  final double lng;
  final double? accuracyMeters;
  final double? altitudeMeters;
  final double? speedMps;

  const TrazaPunto({
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

  factory TrazaPunto.fromJson(Map<String, dynamic> json) => TrazaPunto(
        capturedAt: DateTime.parse(json['captured_at'] as String),
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        accuracyMeters: (json['accuracy_m'] as num?)?.toDouble(),
        altitudeMeters: (json['altitude_m'] as num?)?.toDouble(),
        speedMps: (json['speed_mps'] as num?)?.toDouble(),
      );
}

/// A manually-recorded GPS track ("traza"). The unit of synchronisation: one
/// outbox job pushes the whole track (header + points) in a single HTTP
/// request to `POST /positions/batch`.
///
/// `endedAt == null` means the traza is still open (recording in progress or
/// left open by a crash); the local store enforces at most one open traza
/// per operator.
class TrazaEntity implements Syncable {
  TrazaEntity({
    required this.operadorId,
    required this.startedAt,
    this.endedAt,
    List<TrazaPunto>? points,
    String? name,
    String? clientId,
    this.id,
    DateTime? updatedAt,
  })  : _clientId = clientId ?? const Uuid().v4(),
        _updatedAt = updatedAt ?? DateTime.now(),
        points = points ?? <TrazaPunto>[],
        _name = _clampName(name ?? _defaultName(startedAt));

  final String _clientId;
  final DateTime _updatedAt;
  String _name;

  int? id;
  int operadorId;
  DateTime startedAt;
  DateTime? endedAt;
  List<TrazaPunto> points;

  /// Human-readable label, defaulted at creation to `'Traza yyyy-MM-dd HH:mm'`
  /// (local time of [startedAt]). Truncated to 100 chars on assignment.
  String get name => _name;
  set name(String value) => _name = _clampName(value);

  @override
  String get clientId => _clientId;

  @override
  String? get remoteId => id?.toString();

  @override
  DateTime get updatedAt => _updatedAt;

  static String _clampName(String value) =>
      value.length > 100 ? value.substring(0, 100) : value;

  static String _defaultName(DateTime startedAt) =>
      'Traza ${DateFormat('yyyy-MM-dd HH:mm').format(startedAt.toLocal())}';

  @override
  Map<String, dynamic> toJson() => {
        'traza_client_id': clientId,
        if (id != null) 'remote_id': id,
        'operador_id': operadorId,
        'name': name,
        'started_at': startedAt.toIso8601String(),
        if (endedAt != null) 'ended_at': endedAt!.toIso8601String(),
        'points': points.map((p) => p.toJson()).toList(),
      };

  factory TrazaEntity.fromJson(Map<String, dynamic> json) => TrazaEntity(
        clientId: json['traza_client_id'] as String?,
        id: json['remote_id'] as int?,
        operadorId: (json['operador_id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String?,
        startedAt: DateTime.parse(json['started_at'] as String),
        endedAt: json['ended_at'] == null
            ? null
            : DateTime.parse(json['ended_at'] as String),
        points: ((json['points'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => TrazaPunto.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrazaEntity && other._clientId == _clientId;

  @override
  int get hashCode => _clientId.hashCode;
}
