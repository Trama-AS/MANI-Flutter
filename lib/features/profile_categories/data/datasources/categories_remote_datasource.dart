import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mani/core/network/api_gateway_client.dart';

/// Acceso a categorías del aliado a través del API Gateway (ADR-0019 / ADR-0027).
abstract interface class CategoriesRemoteDataSource {
  Future<List<Map<String, dynamic>>> listarCategoriasTenant();
  Future<List<String>> obtenerMisCategorias();
  Future<List<String>> guardarMisCategorias(List<String> categoriaIds);
}

class SupabaseCategoriesDataSource implements CategoriesRemoteDataSource {
  SupabaseCategoriesDataSource(
    SupabaseClient _, {
    ApiGatewayClient? gatewayClient,
  }) : _gatewayClient = gatewayClient ?? ApiGatewayClient();

  final ApiGatewayClient _gatewayClient;

  @override
  Future<List<Map<String, dynamic>>> listarCategoriasTenant() async {
    final res = await _gatewayClient.get('/api/v1/core/catalog/categories');
    final data = res['data'] ?? res['categories'] ?? res['categorias'];
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    }
    return const [];
  }

  @override
  Future<List<String>> obtenerMisCategorias() async {
    final res = await _gatewayClient.get('/api/v1/core/profiles/me/categories');
    final data = res['data'] ?? res['categoryIds'] ?? res['categoria_ids'];
    if (data is List) {
      return data.map((e) => e.toString()).toList(growable: false);
    }
    return const [];
  }

  @override
  Future<List<String>> guardarMisCategorias(List<String> categoriaIds) async {
    final res = await _gatewayClient.post(
      '/api/v1/core/profiles/me/categories',
      body: {'categoria_ids': categoriaIds},
    );
    final data = res['data'] ?? res['categoryIds'] ?? categoriaIds;
    if (data is List) {
      return data.map((e) => e.toString()).toList(growable: false);
    }
    return categoriaIds;
  }
}
