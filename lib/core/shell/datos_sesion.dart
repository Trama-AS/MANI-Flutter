import 'package:mani/core/network/gateway_client.dart';

/// Lo que la cabecera muestra de la sesión: quién entró y en qué tenant.
class DatosSesion {
  const DatosSesion({required this.nombreUsuario, this.nombreTenant});

  final String nombreUsuario;

  /// `null` si no se pudo resolver; la cabecera lo omite en lugar de fallar.
  final String? nombreTenant;
}

/// Fuente de los datos de la cabecera, separada para probar el shell sin red.
abstract interface class FuenteDatosSesion {
  Future<DatosSesion> cargar();
}

/// Resuelve la cabecera contra Core por el Gateway (US-11.2.1 / SCRUM-1444).
///
/// Todo sale de una sola consulta, `GET /api/v1/core/profiles/me` (SCRUM-854):
/// el nombre del usuario y, si el perfil lo trae, el nombre del tenant.
///
/// No se usa `GET /api/v1/core/tenants` para buscar el tenant: ese endpoint
/// devuelve todos los tenants del sistema y la respuesta completa llegaría al
/// navegador de cualquier usuario (hallazgo de QA en el PR #62). Mientras el
/// perfil no traiga el nombre del tenant, la cabecera lo omite.
class GatewayFuenteDatosSesion implements FuenteDatosSesion {
  GatewayFuenteDatosSesion(this._gateway);

  final GatewayClient _gateway;

  @override
  Future<DatosSesion> cargar() async {
    final res = await _gateway.get('/api/v1/core/profiles/me');
    final perfil = res['profile'] is Map<String, dynamic>
        ? res['profile'] as Map<String, dynamic>
        : res;
    final nombre = (perfil['fullName'] ?? perfil['nombre'] ?? '')
        .toString()
        .trim();

    return DatosSesion(
      nombreUsuario: nombre.isEmpty ? 'Usuario' : nombre,
      nombreTenant: _nombreTenant(perfil),
    );
  }

  /// Acepta `tenantName`, `tenant_name` o un objeto `tenant` con `name` o
  /// `nombre`. Cualquier otra forma, o un texto vacío, deja `null`.
  String? _nombreTenant(Map<String, dynamic> perfil) {
    final tenant = perfil['tenant'];
    final valor =
        perfil['tenantName'] ??
        perfil['tenant_name'] ??
        (tenant is Map ? (tenant['name'] ?? tenant['nombre']) : null);
    final texto = valor?.toString().trim();
    return (texto == null || texto.isEmpty) ? null : texto;
  }
}
