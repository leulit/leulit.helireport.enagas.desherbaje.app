import 'package:uuid/uuid.dart';

import '../../core/sync/contracts/syncable.dart';
import 'json_parsing_utils.dart';

/// Mensaje asociado a un segmento. Implementa [Syncable] con identidad
/// estable por [clientId] (UUID v4); el `id` entero del backend viaja en
/// [remoteId].
class MensajeSegmentoEntity implements Syncable {
  MensajeSegmentoEntity({
    this.id,
    required this.segmentoId,
    required this.mensaje,
    this.enviadoPor,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? clientId,
    this.segmentoClientId,
  })  : _clientId = clientId ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        _updatedAt = updatedAt ?? DateTime.now();

  final String _clientId;

  int? id;
  int segmentoId;

  /// `clientId` (UUID local) del segmento propietario. Vínculo estable local:
  /// `segmentoId` (remoto) vale 0 mientras el segmento no ha sincronizado, así
  /// que las lecturas locales filtran por este campo, no por `segmentoId`.
  String? segmentoClientId;
  String mensaje;
  int? enviadoPor;
  DateTime createdAt;
  DateTime _updatedAt;

  void touchUpdated() {
    _updatedAt = DateTime.now();
  }

  factory MensajeSegmentoEntity.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String key, DateTime fallback) {
      try {
        final raw = json[key];
        if (raw == null) return fallback;
        return DateTime.parse(raw.toString());
      } catch (_) {
        return fallback;
      }
    }

    return MensajeSegmentoEntity(
      id: readJsonDataUtil<int?>(json, 'id', null),
      clientId: readJsonDataUtil<String?>(json, 'client_id', null),
      segmentoId: readJsonDataUtil<int>(json, 'segmento_id', 0),
      segmentoClientId:
          readJsonDataUtil<String?>(json, 'segmento_client_id', null),
      mensaje: readJsonDataUtil<String>(json, 'mensaje', ''),
      enviadoPor: readJsonDataUtil<int?>(json, 'enviado_por', null),
      createdAt: parseDate('created_at', DateTime.now()),
      updatedAt: parseDate('updated_at', DateTime.now()),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'client_id': clientId,
        'segmento_id': segmentoId,
        'segmento_client_id': segmentoClientId,
        'mensaje': mensaje,
        'enviado_por': enviadoPor,
        'created_at': createdAt.toIso8601String(),
        'updated_at': _updatedAt.toIso8601String(),
      };

  @override
  String get clientId => _clientId;

  @override
  String? get remoteId => id?.toString();

  @override
  DateTime get updatedAt => _updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MensajeSegmentoEntity && other._clientId == _clientId;

  @override
  int get hashCode => _clientId.hashCode;

  @override
  String toString() =>
      'MensajeSegmentoEntity(clientId: $_clientId, id: $id, segmentoId: $segmentoId)';
}
