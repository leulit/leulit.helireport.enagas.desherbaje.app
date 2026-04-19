import '../../core/api_endpoints.dart';

/// Información de un CT (Centro de Transformación) asociado al operador
/// logueado. El identificador canónico es [id] (entero, mismo que devuelve el
/// backend en `ct_id`).
class CtInfo {
  /// Identificador del CT en el backend.
  final int id;

  /// Nombre legible del CT.
  final String nombre;

  /// Nombre de fichero usado para los tracks de gasoductos
  /// (`/tracks/json/{filename}-gasoductos.json`). Por defecto coincide con
  /// [nombre], pero el backend puede personalizarlo.
  final String filename;

  CtInfo({
    required this.id,
    required this.nombre,
    required this.filename,
  });

  String get gasoductosUrl => ApiEndpoints.gasoductosTrack(filename);

  String get pkUrl => ApiEndpoints.pkTrack(filename);

  factory CtInfo.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['ct_id'] ?? json['ct'];
    final id = rawId is int
        ? rawId
        : int.tryParse(rawId?.toString() ?? '') ?? 0;
    final nombre = (json['nombre'] ?? json['name'] ?? '').toString();
    final filename = (json['filename'] ?? nombre).toString();
    return CtInfo(id: id, nombre: nombre, filename: filename);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'filename': filename,
      };
}
