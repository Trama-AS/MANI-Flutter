import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';

/// Categoría activa del tenant, tal como la necesita un formulario de registro.
class CategoriaPublica {
  const CategoriaPublica({required this.id, required this.nombre});

  final String id;
  final String nombre;
}

/// Catálogo público del tenant para las pantallas sin sesión (registro de
/// aliado y de aliado empresa). `GET /api/v1/core/catalog` es pública en el
/// Gateway y Core resuelve el tenant por `X-Tenant-Slug` (ADR-0018).
///
/// Reemplaza los UUID de categorías fijos en las pantallas, que solo existían
/// en la semilla de desarrollo y rompían el registro en QA.
class CatalogoPublicoDataSource {
  const CatalogoPublicoDataSource(this._gateway);

  static const rutaCatalogo = '/api/v1/core/catalog';
  static const headerTenantSlug = 'X-Tenant-Slug';

  final GatewayClient _gateway;

  Future<List<CategoriaPublica>> categoriasActivas(String tenantSlug) async {
    final res = await _gateway.get(
      rutaCatalogo,
      headers: {headerTenantSlug: tenantSlug},
    );
    final lista = res['categories'];
    if (lista is! List) {
      throw const GatewayException(
        message: 'Respuesta inesperada del servidor',
        statusCode: 502,
      );
    }
    return [
      for (final e in lista.whereType<Map>())
        if (e['active'] != false && e['id'] is String && e['name'] is String)
          CategoriaPublica(id: e['id'] as String, nombre: e['name'] as String),
    ];
  }
}
