import 'package:supabase_flutter/supabase_flutter.dart';

/// Respuesta a un 401 del Gateway (US-11.2.2 / SCRUM-1445).
///
/// Intenta [refrescar] una vez. Si no hay sesión nueva, o el refresco falla,
/// ejecuta [cerrar] y devuelve `false` para que [GatewayClient] no reintente.
/// Al cerrarse la sesión, el `redirect` del router manda al login.
Future<bool> refrescarOCerrar({
  required Future<bool> Function() refrescar,
  required Future<void> Function() cerrar,
}) async {
  var refrescada = false;
  try {
    refrescada = await refrescar();
  } catch (_) {
    refrescada = false;
  }
  if (refrescada) return true;
  try {
    await cerrar();
  } catch (_) {
    // El cierre es local; si falla, el redirect igual verá una sesión
    // vencida en el próximo intento y no hay nada más que hacer aquí.
  }
  return false;
}

/// [refrescarOCerrar] sobre Supabase Auth. El cierre es solo local
/// (`SignOutScope.local`): no depende de la red, que es justo lo que puede
/// estar fallando.
Future<bool> refrescarOCerrarSesion(GoTrueClient auth) => refrescarOCerrar(
  refrescar: () async => (await auth.refreshSession()).session != null,
  cerrar: () => auth.signOut(scope: SignOutScope.local),
);
