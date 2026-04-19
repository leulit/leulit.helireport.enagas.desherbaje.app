abstract class Syncable {
  String get clientId;

  String? get remoteId;

  DateTime get updatedAt;

  Map<String, dynamic> toJson();
}
