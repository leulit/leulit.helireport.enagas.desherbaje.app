/// Roles soportados en el backend. El campo `profile` del usuario llega como
/// string; usar [userRoleFromString] para convertirlo de forma segura.
enum UserRole {
  administrador,
  operador,
  supervisor,
  readonly,
}

UserRole? userRoleFromString(String? value) {
  if (value == null || value.isEmpty) return null;
  final v = value.toLowerCase().trim();
  for (final r in UserRole.values) {
    if (r.name == v) return r;
  }
  return null;
}

/// Grupos organizativos a los que puede pertenecer un usuario. El backend
/// guarda el nombre en mayúsculas (`ENAGAS`, ...). [userGroupFromString]
/// normaliza la entrada.
enum UserGroups {
  enagas,
  leulit,
  contratista,
}

UserGroups? userGroupFromString(String? value) {
  if (value == null || value.isEmpty) return null;
  final v = value.toLowerCase().trim();
  for (final g in UserGroups.values) {
    if (g.name == v) return g;
  }
  return null;
}
