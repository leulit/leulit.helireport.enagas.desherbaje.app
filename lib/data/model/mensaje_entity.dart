import '../../data/model/base_model.dart';

class MensajeEntity with BaseModelMixin {
  MensajeEntity({
    this.id = 0,
    this.incidentId,
    this.senderUserId,
    this.senderUserName,
    this.senderUserProfile,
    this.senderUserGrupo,
    this.mensaje = '',
    this.sentAt,
    this.messageType,
  });

  int id;
  int? incidentId;
  int? senderUserId;
  String? senderUserName;
  String? senderUserProfile;
  String? senderUserGrupo;
  String mensaje;  
  DateTime? sentAt;
  String? messageType;

  MensajeEntity.fromJson(Map<String, dynamic> json)
    : id = 0,
      incidentId = null,
      senderUserId = null,
      senderUserName = null,
      senderUserProfile = null,
      senderUserGrupo = null,
      mensaje = '',
      sentAt = null,
      messageType = null {
    id = readJsonData<int>(json, 'id', 0);

    final incidentRaw = readJsonData<int>(json, 'incident_id', 0);
    if (json.containsKey('incident_id') && json['incident_id'] == null) {
      incidentId = null;
    } else if (incidentRaw != 0) {
      incidentId = incidentRaw;
    }

    final senderRaw = readJsonData<int>(json, 'sender_user_id', 0);
    if (json.containsKey('sender_user_id') && json['sender_user_id'] == null) {
      senderUserId = null;
    } else if (senderRaw != 0) {
      senderUserId = senderRaw;
    }

    final senderNameRaw = readJsonData<String>(json, 'sender_user_name', '').trim();
    senderUserName = senderNameRaw.isEmpty ? null : senderNameRaw;

    final senderProfileRaw = readJsonData<String>(json, 'sender_user_profile', '').trim();
    senderUserProfile = senderProfileRaw.isEmpty ? null : senderProfileRaw;

    final senderGrupoRaw = readJsonData<String>(json, 'sender_user_grupo', '').trim();
    senderUserGrupo = senderGrupoRaw.isEmpty ? null : senderGrupoRaw;

    mensaje = readJsonData<String>(json, 'mensaje', '');

    if (json.containsKey('sent_at') && json['sent_at'] != null) {
      sentAt = readJsonDateTime(json, 'sent_at', DateTime.now());
    }

    final typeRaw = readJsonData<String>(json, 'message_type', '').trim();
    messageType = typeRaw.isEmpty ? null : typeRaw;
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};

    if (id > 0) {
      setValueInMap(data, 'id', id);
    }

    setValueInMap(data, 'incident_id', incidentId);
    setValueInMap(data, 'sender_user_id', senderUserId);
    setValueInMap(data, 'sender_user_name', senderUserName);
    setValueInMap(data, 'sender_user_profile', senderUserProfile);
    setValueInMap(data, 'sender_user_grupo', senderUserGrupo);
    setValueInMap(data, 'mensaje', mensaje);
    setValueInMap(data, 'sent_at', sentAt?.toIso8601String());
    setValueInMap(data, 'message_type', messageType);

    data.removeWhere((_, value) => value == null);
    return data;
  }

  MensajeEntity copyWith({
    int? id,
    int? incidentId,
    int? senderUserId,
    String? senderUserName,
    String? senderUserProfile,
    String? senderUserGrupo,
    String? mensaje,
    DateTime? sentAt,
    String? messageType,
  }) {
    return MensajeEntity(
      id: id ?? this.id,
      incidentId: incidentId ?? this.incidentId,
      senderUserId: senderUserId ?? this.senderUserId,
      senderUserName: senderUserName ?? this.senderUserName,
      senderUserProfile: senderUserProfile ?? this.senderUserProfile,
      senderUserGrupo: senderUserGrupo ?? this.senderUserGrupo,
      mensaje: mensaje!,
      sentAt: sentAt ?? this.sentAt,
      messageType: messageType ?? this.messageType,
    );
  }
}
