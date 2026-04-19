import '../../core/sync/contracts/syncable.dart';

enum TipoFoto { antes, despues }
enum SyncStatus { pending, uploading, uploaded, error }

class ImagenSegmentoEntity implements Syncable {
  final String localId;
  int? remoteIntId;
  final int actividadId;
  final int? segmentoId;
  final String localPath;
  String? remoteUrl;
  final TipoFoto tipoFoto;
  final DateTime capturedAt;
  final double? latitude;
  final double? longitude;
  SyncStatus syncStatus;

  ImagenSegmentoEntity({
    required this.localId,
    this.remoteIntId,
    required this.actividadId,
    this.segmentoId,
    required this.localPath,
    this.remoteUrl,
    required this.tipoFoto,
    required this.capturedAt,
    this.latitude,
    this.longitude,
    this.syncStatus = SyncStatus.pending,
  });

  @override
  String get clientId => localId;

  @override
  String? get remoteId => remoteIntId?.toString();

  @override
  DateTime get updatedAt => capturedAt;

  factory ImagenSegmentoEntity.fromMap(Map<String, dynamic> map) {
    return ImagenSegmentoEntity(
      localId: map['local_id'] as String,
      remoteIntId: map['remote_id'] as int?,
      actividadId: map['actividad_id'] as int,
      segmentoId: map['segmento_id'] as int?,
      localPath: map['local_path'] as String,
      remoteUrl: map['remote_url'] as String?,
      tipoFoto: TipoFoto.values.firstWhere(
        (e) => e.name == map['tipo_foto'],
        orElse: () => TipoFoto.antes,
      ),
      capturedAt: DateTime.parse(map['captured_at'] as String),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      syncStatus: SyncStatus.values.firstWhere(
        (e) => e.name == map['sync_status'],
        orElse: () => SyncStatus.pending,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'local_id': localId,
    'remote_id': remoteIntId,
    'actividad_id': actividadId,
    'segmento_id': segmentoId,
    'local_path': localPath,
    'remote_url': remoteUrl,
    'tipo_foto': tipoFoto.name,
    'captured_at': capturedAt.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'sync_status': syncStatus.name,
  };

  /// Alias of [toMap] to satisfy the [Syncable] contract without duplicating
  /// serialization logic. SQLite schema and key names remain unchanged.
  @override
  Map<String, dynamic> toJson() => toMap();
}
