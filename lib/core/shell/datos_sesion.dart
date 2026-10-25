import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';

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
/// - El nombre sale de `GET /api/v1/core/profiles/me` (SCRUM-854).
/// - El tenant sale de `GET /api/v1/core/tenants` buscando el `tenantId` del
///   perfil, porque el perfil solo trae el id. Si esa consulta falla, la
///   cabecera se muestra sin tenant: no es motivo para tumbar el menú.
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
    final tenantId = (perfil['tenantId'] ?? perfil['tenant_id'])?.toString();

    return DatosSesion(
      nombreUsuario: nombre.isEmpty ? 'Usuario' : nombre,
      nombreTenant: tenantId == null ? null : await _nombreTenant(tenantId),
    );
  }

  Future<String?> _nombreTenant(String tenantId) async {
    try {
      final res = await _gateway.get('/api/v1/core/tenants');
      final data = res['data'];
      if (data is! List) return null;
      for (final t in data) {
        if (t is Map && t['id']?.toString() == tenantId) {
          final nombre = (t['name'] ?? t['nombre'])?.toString().trim();
          return (nombre == null || nombre.isEmpty) ? null : nombre;
        }
      }
      return null;
    } on GatewayException {
      return null;
    }
  }
}
