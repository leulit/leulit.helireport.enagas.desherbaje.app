class CtInfo {
  final String ct;
  final String nombre;
  final String filename;

  CtInfo({required this.ct, required this.nombre, required this.filename});

  String get gasoductosUrl =>
      'https://enagastool.helireport.com/tracks/json/$filename-gasoductos.json';

  factory CtInfo.fromJson(Map<String, dynamic> json) {
    final ct = (json['ct'] ?? json['code'] ?? '').toString();
    final nombre = (json['nombre'] ?? json['name'] ?? ct).toString();
    return CtInfo(ct: ct, nombre: nombre, filename: nombre);
  }

  factory CtInfo.fromString(String ctCode) {
    return CtInfo(
      ct: ctCode,
      nombre: ctCode,
      filename: ctCode,
    );
  }
}
