enum TipoFoto { antes, despues }
enum SyncStatus { pending, uploading, uploaded, error }

class ImagenSegmentoEntity {
  final String localId;
  int? remoteId;
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
    this.remoteId,
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

  factory ImagenSegmentoEntity.fromMap(Map<String, dynamic> map) {
    return ImagenSegmentoEntity(
      localId: map['local_id'] as String,
      remoteId: map['remote_id'] as int?,
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
    'remote_id': remoteId,
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
}
