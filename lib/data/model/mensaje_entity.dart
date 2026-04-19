import 'json_parsing_utils.dart';

/// Entidad mapeada a la tabla `mensajes_segmento` del backend.
class MensajeSegmentoEntity {
  MensajeSegmentoEntity({
    this.id,
    required this.segmentoId,
    required this.mensaje,
    this.enviadoPor,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  int? id;
  int segmentoId;
  String mensaje;
  int? enviadoPor;
  DateTime createdAt;
  DateTime updatedAt;

  factory MensajeSegmentoEntity.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String key) {
      try {
        final raw = json[key];
        if (raw == null) return DateTime.now();
        return DateTime.parse(raw.toString());
      } catch (_) {
        return DateTime.now();
      }
    }

    return MensajeSegmentoEntity(
      id:         readJsonDataUtil<int?>(json, 'id', null),
      segmentoId: readJsonDataUtil<int>(json, 'segmento_id', 0),
      mensaje:    readJsonDataUtil<String>(json, 'mensaje', ''),
      enviadoPor: readJsonDataUtil<int?>(json, 'enviado_por', null),
      createdAt:  parseDate('created_at'),
      updatedAt:  parseDate('updated_at'),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'segmento_id': segmentoId,
        'mensaje': mensaje,
        'enviado_por': enviadoPor,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MensajeSegmentoEntity && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'MensajeSegmentoEntity(id: $id, segmentoId: $segmentoId, enviadoPor: $enviadoPor)';
}
