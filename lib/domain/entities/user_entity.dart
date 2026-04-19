import '../../data/model/base_model.dart';
import 'user_role.dart';

/// Vínculo usuario↔CT con perfil y visibilidad. Espejo de la fila
/// `user_cts` del backend.
class UserCt with BaseModelMixin {
  int id = 0;
  int idusuario = 0;
  int ctid = 0;
  String ct = '';
  String perfil = '';
  bool visible = true;

  UserCt();

  static UserCt empty() => UserCt();

  UserCt.fromJson(Map<dynamic, dynamic> parsedJson) {
    id        = readJsonData<int>(parsedJson, 'id', 0);
    idusuario = readJsonData<int>(parsedJson, 'idusuario', 0);
    ct        = readJsonData<String>(parsedJson, 'ct', '');
    perfil    = readJsonData<String>(parsedJson, 'perfil', '');
    ctid      = readJsonData<int>(parsedJson, 'ct_id', 0);
    visible   = readJsonData<bool>(parsedJson, 'visible', true);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'idusuario': idusuario,
        'ct': ct,
        'perfil': perfil,
        'ct_id': ctid,
        'visible': visible,
      };
}

/// Modelo de usuario logueado. Reemplaza al antiguo `UserEntity`.
class UserModel with BaseModelMixin {
  int id = 0;
  int idServer = 0;
  String usuario = '';
  String password = '';
  String email = '';
  String profile = '';
  String nombre = '';
  List<UserCt> cts = [];
  String grupo = '';
  DateTime? lastlogin;

  /// Token JWT/sesión. Se completa en el `AuthDataProvider` tras el login;
  /// no llega como campo del usuario en el JSON.
  String token = '';

  UserModel();

  /// Rol parseado desde [profile]. Cae a [UserRole.readonly] si no se
  /// reconoce.
  UserRole get role => userRoleFromString(profile) ?? UserRole.readonly;

  /// Grupo tipado desde [grupo]. `null` si no se reconoce o está vacío.
  UserGroups? get group => userGroupFromString(grupo.toLowerCase());

  UserModel.fromJson(Map<dynamic, dynamic> parsedJson) {
    id        = readJsonData<int>(parsedJson, 'id', 0);
    usuario   = readJsonData<String>(parsedJson, 'usuario', '');
    password  = readJsonData<String>(parsedJson, 'password', '');
    email     = readJsonData<String>(parsedJson, 'email', '');
    profile   = readJsonData<String>(parsedJson, 'profile', '');
    nombre    = readJsonData<String>(parsedJson, 'nombre', '');
    grupo     = readJsonData<String>(parsedJson, 'grupo', '');
    token     = readJsonData<String>(parsedJson, 'token', '');
    lastlogin = readJsonDateTime(parsedJson, 'lastlogin', DateTime.now());

    cts = [];
    final raw = parsedJson['cts'];
    if (raw is List) {
      for (final ctItem in raw) {
        if (ctItem is Map) {
          cts.add(UserCt.fromJson(ctItem));
        }
      }
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'usuario': usuario,
        'password': password,
        'email': email,
        'profile': profile,
        'nombre': nombre,
        'grupo': grupo,
        'token': token,
        'lastlogin': lastlogin?.toIso8601String(),
        'cts': cts.map((ct) => ct.toJson()).toList(),
      };

  bool isEnagasUser() => grupo.toUpperCase() == 'ENAGAS';

  /// Nombres legibles de los CTs del usuario.
  List<String> ctsName() => cts.map((e) => e.ct).toList();

  /// IDs (ctid) de los CTs del usuario.
  List<int> ctsId() => cts.map((e) => e.ctid).toList();

  String? ctNameById(int id) {
    try {
      return cts.firstWhere((c) => c.ctid == id).ct;
    } catch (_) {
      return null;
    }
  }

  bool isOperador() => role == UserRole.operador;

  /// Acceso al módulo Vigilancias — abierto a todos los roles.
  bool get vigilancias => true;

  /// Acceso al módulo Desherbaje — sólo administradores.
  bool get desherbaje => role == UserRole.administrador;

  /// Acceso al módulo Inkoland — sólo administradores.
  bool get inkoland => role == UserRole.administrador;
}
