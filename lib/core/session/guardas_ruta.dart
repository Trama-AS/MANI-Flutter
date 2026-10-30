import 'package:mani/core/session/rol_usuario.dart';
import 'package:mani/core/shell/menu_por_rol.dart';

/// Ruta a la que vuelve quien no tiene sesión o la perdió.
const rutaLogin = '/login';

/// Pantalla de inicio por tipo de usuario (US-11.2.3 / SCRUM-1446).
const rutaInicio = '/inicio';

const _todosLosRoles = {
  RolUsuario.cliente,
  RolUsuario.aliado,
  RolUsuario.adminTenant,
  RolUsuario.adminPlataforma,
  RolUsuario.desconocido,
};

/// Roles que pueden abrir cada prefijo de ruta con sesión (US-11.2.2 /
/// SCRUM-1445). El orden importa: gana el primer prefijo que coincide.
///
/// Esto evita que la app pinte una pantalla que no le corresponde al rol; no
/// es la autorización. Core y Dispatch siguen respondiendo 403 con el token
/// verificado (T4, T7), y esa es la barrera que cuenta.
const _rolesPorPrefijo = <String, Set<RolUsuario>>{
  rutaInicio: _todosLosRoles,
  '/admin/': {RolUsuario.adminTenant},
  // Administración global de tenants (SCRUM-901): solo el permiso de plataforma.
  '/plataforma/': {RolUsuario.adminPlataforma},
  '/aliado/': {RolUsuario.aliado},
  '/categories': {RolUsuario.aliado},
  '/cliente/': {RolUsuario.cliente},
  // El cliente configura las reglas de su sitio y el aliado las consulta
  // antes de programar (US-02.2.3).
  '/sitios/': {RolUsuario.cliente, RolUsuario.aliado, RolUsuario.adminTenant},
  '/perfil/': _todosLosRoles,
};

/// `true` si el [rol] puede abrir la ruta con sesión [ubicacion]. Una ruta
/// con sesión que no figura en la tabla se niega: así una pantalla nueva no
/// queda abierta a todos los roles por olvido.
bool rolPuedeAbrir(RolUsuario rol, String ubicacion) {
  for (final entrada in _rolesPorPrefijo.entries) {
    if (ubicacion == entrada.key || ubicacion.startsWith(entrada.key)) {
      return entrada.value.contains(rol);
    }
  }
  return false;
}

/// Primera pantalla del rol: la primera entrada de su menú superior, que
/// desde SCRUM-1446 es [rutaInicio] para todos.
String rutaInicioPara(RolUsuario rol) => entradasMenuPara(rol).first.ruta;

/// Decide la redirección del router. Devuelve `null` si se puede seguir.
///
/// - Sin sesión, toda ruta con sesión lleva a [rutaLogin].
/// - Con sesión, una ruta de otro rol lleva al inicio del rol propio.
/// - Con sesión, el login lleva al inicio del rol (SCRUM-1446): quien ya
///   entró no vuelve a ver el formulario al abrir la app.
/// - El resto de rutas públicas (registros) no se tocan aquí.
String? resolverRedireccion({
  required String ubicacion,
  required bool esPublica,
  required bool haySesion,
  required RolUsuario rol,
}) {
  if (esPublica) {
    return haySesion && ubicacion == rutaLogin ? rutaInicioPara(rol) : null;
  }
  if (!haySesion) return rutaLogin;
  if (rolPuedeAbrir(rol, ubicacion)) return null;
  return rutaInicioPara(rol);
}
