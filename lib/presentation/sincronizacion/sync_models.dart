/// Identificador estable de cada fila de "datos maestros" en la página de
/// sincronización. Solo se descargan; nunca se suben.
enum MasterDataKind {
  segmentos,
  user,
  pks,
  hitos,
  gasoductos,
  posicionesFijas,
}

extension MasterDataKindLabel on MasterDataKind {
  String get title {
    switch (this) {
      case MasterDataKind.user:
        return 'Datos de usuario';
      case MasterDataKind.gasoductos:
        return 'Trazas de gasoductos';
      case MasterDataKind.pks:
        return 'Puntos kilométricos';
      case MasterDataKind.hitos:
        return 'Hitos';
      case MasterDataKind.segmentos:
        return 'Segmentos';
      case MasterDataKind.posicionesFijas:
        return 'Posiciones fijas';
    }
  }

  String get description {
    switch (this) {
      case MasterDataKind.user:
        return 'Perfil del operador y CTs asignados.';
      case MasterDataKind.gasoductos:
        return 'Geometría de las trazas de gasoductos para uso en mapa.';
      case MasterDataKind.pks:
        return 'Puntos kilométricos asociados a cada CT.';
      case MasterDataKind.hitos:
        return 'Hitos asociados a cada CT.';
      case MasterDataKind.segmentos:
        return 'Lista de segmentos asignados al operador.';
      case MasterDataKind.posicionesFijas:
        return 'Pendiente de backend.';
    }
  }
}

/// Estado por fila de master data en la UI.
enum MasterDataStatus { idle, downloading, success, error, unavailable }

/// Modelo de fila de master data expuesto por el controller.
class MasterDataRow {
  final MasterDataKind kind;
  final MasterDataStatus status;
  final DateTime? lastDownloadAt;
  final String? errorMessage;

  /// Progreso 0.0–1.0 de la descarga en curso. `null` significa indeterminado
  /// (o no aplica para esta fila).
  final double? progress;

  /// Etiqueta opcional asociada al progreso, p.ej. `"3 / 12"`.
  final String? progressLabel;

  /// NF-14: true cuando la última carga de master-data se sirvió desde la
  /// caché local en lugar de hacer un fetch de red real.
  final bool servedFromCache;

  const MasterDataRow({
    required this.kind,
    this.status = MasterDataStatus.idle,
    this.lastDownloadAt,
    this.errorMessage,
    this.progress,
    this.progressLabel,
    this.servedFromCache = false,
  });

  MasterDataRow copyWith({
    MasterDataStatus? status,
    DateTime? lastDownloadAt,
    String? errorMessage,
    double? progress,
    String? progressLabel,
    bool? servedFromCache,
    bool clearError = false,
    bool clearLastDownloadAt = false,
    bool clearProgress = false,
    bool clearProgressLabel = false,
    bool clearServedFromCache = false,
  }) {
    return MasterDataRow(
      kind: kind,
      status: status ?? this.status,
      lastDownloadAt: clearLastDownloadAt
          ? null
          : (lastDownloadAt ?? this.lastDownloadAt),
      errorMessage:
          clearError ? null : (errorMessage ?? this.errorMessage),
      progress: clearProgress ? null : (progress ?? this.progress),
      progressLabel:
          clearProgressLabel ? null : (progressLabel ?? this.progressLabel),
      servedFromCache: clearServedFromCache
          ? false
          : (servedFromCache ?? this.servedFromCache),
    );
  }
}
