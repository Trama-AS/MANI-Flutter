import 'dart:convert';

/// Rol con el que la app decide qué mostrar (US-11.2.1 / SCRUM-1444).
///
/// Solo gobierna la presentación: la autorización real la aplican el Gateway
/// y los servicios con el token verificado (T4, T7). Un rol que no se
/// reconoce cae en [desconocido] y no abre ninguna entrada de negocio.
enum RolUsuario { cliente, aliado, adminTenant, desconocido }

/// Traduce el claim `app_metadata.user_role` (o `rol`) al rol de la app.
///
/// El Custom Access Token Hook (CFG-12) emite el claim en español minúscula
/// (`cliente`, `aliado`, `admin_tenant`); se aceptan también los nombres de
/// dominio de Core (`CLIENT`, `ALLY`, `ADMIN`) para no depender del formato.
RolUsuario rolDesdeClaim(String? claim) {
  switch (claim?.trim().toLowerCase()) {
    case 'cliente':
    case 'client':
      return RolUsuario.cliente;
    case 'aliado':
    case 'ally':
      return RolUsuario.aliado;
    case 'admin_tenant':
    case 'admin':
      return RolUsuario.adminTenant;
    default:
      return RolUsuario.desconocido;
  }
}

/// Lee el rol del payload del access token.
///
/// El hook escribe los claims en el JWT, no en `auth.users`, así que
/// `currentUser.appMetadata` no siempre los trae: por eso se decodifica el
/// token. No se verifica la firma porque el dato solo decide qué se pinta;
/// el Gateway sí la verifica en cada petición. Un token mal formado
/// devuelve [RolUsuario.desconocido].
RolUsuario rolDesdeAccessToken(String? accessToken) {
  final claims = _payload(accessToken);
  final appMetadata = claims?['app_metadata'];
  if (appMetadata is! Map) return RolUsuario.desconocido;
  final claim = appMetadata['user_role'] ?? appMetadata['rol'];
  return rolDesdeClaim(claim is String ? claim : null);
}

Map<String, dynamic>? _payload(String? token) {
  if (token == null) return null;
  final partes = token.split('.');
  if (partes.length != 3) return null;
  try {
    final json = utf8.decode(base64Url.decode(base64Url.normalize(partes[1])));
    final decoded = jsonDecode(json);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
