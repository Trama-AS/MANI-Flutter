import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mani/core/network/api_gateway_client.dart';

/// Acceso a servicios de categorías a través del API Gateway (ADR-0019 / ADR-0027).
abstract interface class CategoriasRemoteDataSource {
  Future<List<Map<String, dynamic>>> listar();
  Future<Map<String, dynamic>> crear({
    required String nombre,
    required String flujoOperativo,
    required bool activa,
  });

  /// Solo para trazas (log estructurado); nunca se usa para autorizar.
  String? get tenantIdSesion;
}

class SupabaseCategoriasDataSource implements CategoriasRemoteDataSource {
  SupabaseCategoriasDataSource(this._client, {ApiGatewayClient? gatewayClient})
    : _gatewayClient = gatewayClient ?? ApiGatewayClient();

  final SupabaseClient _client;
  final ApiGatewayClient _gatewayClient;

  @override
  Future<List<Map<String, dynamic>>> listar() async {
    final res = await _gatewayClient.get('/api/v1/core/catalog/admin');
    final data = res['data'] ?? res['categories'] ?? res['categorias'];
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    }
    return const [];
  }

  @override
  Future<Map<String, dynamic>> crear({
    required String nombre,
    required String flujoOperativo,
    required bool activa,
  }) async {
    final res = await _gatewayClient.post(
      '/api/v1/core/catalog/admin',
      body: {
        'nombre': nombre,
        'flujo_operativo': flujoOperativo,
        'activa': activa,
      },
    );
    if (res['data'] is Map) {
      return Map<String, dynamic>.from(res['data'] as Map);
    }
    return res;
  }

  @override
  String? get tenantIdSesion {
    final user = _client.auth.currentUser;
    return (user?.appMetadata['tenant_id'] ?? user?.userMetadata?['tenant_id'])
        as String?;
  }
}
