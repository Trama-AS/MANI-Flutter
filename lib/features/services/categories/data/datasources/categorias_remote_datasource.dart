import 'package:mani/core/network/gateway_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso al catálogo de categorías del tenant. `tenant_id` NUNCA se envía:
/// las RPC y el API Gateway lo derivan del JWT de `auth.uid()`.
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

class SupabaseCategoriasDataSource implements CategoriasRemoteDataSource {
  SupabaseCategoriasDataSource(this._client, {GatewayClient? gateway})
    : _gateway = gateway;

  static const _rutaCatalogo = '/api/v1/core/catalog/categories';

  final SupabaseClient _client;
  final GatewayClient? _gateway;

  @override
  Future<List<Map<String, dynamic>>> listar() async {
    final res = await _client.rpc('listar_categorias_admin');
    if (res is! List) {
      return const [];
    }
    return res
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> crear({
    required String nombre,
    required String flujoOperativo,
    required bool activa,
  }) async {
    final res = await _client.rpc(
      'crear_categoria_servicio',
      params: {
        'p_nombre': nombre,
        'p_flujo_operativo': flujoOperativo,
        'p_activa': activa,
      },
    );
    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    throw const PostgrestException(
      message: 'Respuesta inesperada del servidor',
    );
  }

  @override
  Future<Map<String, dynamic>> cambiarEstado({
    required String categoriaId,
    required bool activa,
  }) async {
    final gw = _gateway;
    if (gw != null) {
      final accion = activa ? 'activate' : 'deactivate';
      final res = await gw.patch(
        '$_rutaCatalogo/${Uri.encodeComponent(categoriaId)}/$accion',
        const {},
      );
      if (res['category'] is Map) {
        return Map<String, dynamic>.from(res['category'] as Map);
      }
      return res;
    }
    final res = await _client.rpc(
      'cambiar_estado_categoria_servicio',
      params: {'p_categoria_id': categoriaId, 'p_activa': activa},
    );
    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    throw const PostgrestException(
      message: 'Respuesta inesperada del servidor',
    );
  }

  @override
  String? get tenantIdSesion {
    final user = _client.auth.currentUser;
    return (user?.appMetadata['tenant_id'] ?? user?.userMetadata?['tenant_id'])
        as String?;
  }
}
