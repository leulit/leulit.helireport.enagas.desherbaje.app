import 'ct_info_entity.dart';

class UserEntity {
  final int id;
  final String usuario;
  final String nombre;
  final List<String> cts;
  final List<CtInfo> ctInfos;
  final String token;

  UserEntity({
    required this.id,
    required this.usuario,
    required this.nombre,
    required this.cts,
    required this.ctInfos,
    required this.token,
  });

  factory UserEntity.fromJson(Map<String, dynamic> json, String token) {
    final ctsRaw = json['cts'];
    List<String> ctsList = [];
    List<CtInfo> ctInfosList = [];

    if (ctsRaw is List) {
      for (final item in ctsRaw) {
        if (item is Map<String, dynamic>) {
          final info = CtInfo.fromJson(item);
          ctInfosList.add(info);
          ctsList.add(info.ct);
        } else {
          final s = item.toString().trim();
          ctsList.add(s);
          ctInfosList.add(CtInfo.fromString(s));
        }
      }
    } else if (ctsRaw is String && ctsRaw.isNotEmpty) {
      ctsList = ctsRaw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      ctInfosList = ctsList.map(CtInfo.fromString).toList();
    }

    return UserEntity(
      id: json['id'] as int? ?? 0,
      usuario: json['usuario'] as String? ?? '',
      nombre: json['nombre'] as String? ?? '',
      cts: ctsList,
      ctInfos: ctInfosList,
      token: token,
    );
  }
}
