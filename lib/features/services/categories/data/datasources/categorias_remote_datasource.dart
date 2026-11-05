import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mani/core/session/tenant_sesion.dart';

/// Acceso al catálogo de categorías del tenant. `tenant_id` NUNCA se envía:
/// el API Gateway lo deriva del JWT y se lo inyecta a Core Node.
abstract interface class CategoriasRemoteDataSource {
  Future<List<Map<String, dynamic>>> listar();
  Future<Map<String, dynamic>> crear({
    required String nombre,
    required String flujoOperativo,
    required bool activa,
  });
  Future<Map<String, dynamic>> cambiarEstado({
    required String categoriaId,
    required bool activa,
  });

  /// Solo para trazas (log estructurado); nunca se usa para autorizar.
  String? get tenantIdSesion;
}

/// Todas las operaciones salen por el API Gateway hacia Core Node
/// (`/api/v1/core/catalog/categories`); ninguna llama RPC ni tablas de
/// Supabase (ADR-0022). Supabase solo se usa para leer la sesión local.
class GatewayCategoriasDataSource implements CategoriasRemoteDataSource {
  GatewayCategoriasDataSource(this._gateway, {SupabaseClient? sesion})
    : _sesion = sesion;

  static const _rutaCatalogo = '/api/v1/core/catalog/categories';

  final GatewayClient _gateway;
  final SupabaseClient? _sesion;

  @override
  Future<List<Map<String, dynamic>>> listar() async {
    final res = await _gateway.get(_rutaCatalogo);
    final lista = res['categories'];
    if (lista is! List) {
      throw _respuestaInesperada;
    }
    return lista
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  /// Core crea siempre la categoría activa; si el admin la pidió oculta, se
  /// desactiva enseguida. Si ese segundo paso falla, se devuelve la categoría
  /// tal como quedó (activa) para que la UI muestre el estado real.
  @override
  Future<Map<String, dynamic>> crear({
    required String nombre,
    required String flujoOperativo,
    required bool activa,
  }) async {
    final creada = _categoria(
      await _gateway.postJson(_rutaCatalogo, {
        'name': nombre,
        'flujoOperativo': flujoOperativo,
      }),
    );
    if (activa) {
      return creada;
    }
    try {
      return await cambiarEstado(
        categoriaId: creada['id'] as String,
        activa: false,
      );
    } on GatewayException {
      return creada;
    }
  }

  @override
  Future<Map<String, dynamic>> cambiarEstado({
    required String categoriaId,
    required bool activa,
  }) async {
    final accion = activa ? 'activate' : 'deactivate';
    return _categoria(
      await _gateway.patch(
        '$_rutaCatalogo/${Uri.encodeComponent(categoriaId)}/$accion',
        const <String, dynamic>{},
      ),
    );
  }

  @override
  String? get tenantIdSesion {
    final auth = _sesion?.auth;
    return auth == null ? null : tenantIdDeSesion(auth);
  }

  static Map<String, dynamic> _categoria(Map<String, dynamic> res) {
    final categoria = res['category'];
    if (categoria is! Map) {
      throw _respuestaInesperada;
    }
    return Map<String, dynamic>.from(categoria);
  }

  static const _respuestaInesperada = GatewayException(
    message: 'Respuesta inesperada del servidor',
    statusCode: 502,
  );
}
