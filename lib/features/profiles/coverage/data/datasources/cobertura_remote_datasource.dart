import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mani/core/network/api_gateway_client.dart';

/// Acceso a servicios de cobertura a través del API Gateway (ADR-0019 / ADR-0027).
abstract interface class CoberturaRemoteDataSource {
  Future<List<Map<String, dynamic>>> listarZonas(String? padreId);
  Future<List<Map<String, dynamic>>> buscarZonas(String ciudadId, String texto);
  Future<List<Map<String, dynamic>>> obtenerMiCobertura();
  Future<List<Map<String, dynamic>>> declararCobertura(List<String> zonaIds);

  /// Solo para trazas (log estructurado); nunca se usa para autorizar.
  String? get tenantIdSesion;
}

class SupabaseCoberturaDataSource implements CoberturaRemoteDataSource {
  SupabaseCoberturaDataSource(this._client, {ApiGatewayClient? gatewayClient})
    : _gatewayClient = gatewayClient ?? ApiGatewayClient();

  final SupabaseClient _client;
  final ApiGatewayClient _gatewayClient;

  @override
  Future<List<Map<String, dynamic>>> listarZonas(String? padreId) async {
    final query = padreId != null ? '?padre_id=$padreId' : '';
    final res = await _gatewayClient.get('/api/v1/core/zones$query');
    final data = res['data'] ?? res['zonas'] ?? res['zones'];
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    }
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> buscarZonas(
    String ciudadId,
    String texto,
  ) async {
    final res = await _gatewayClient.get(
      '/api/v1/core/zones/search?ciudad_id=$ciudadId&q=$texto',
    );
    final data = res['data'] ?? res['zonas'];
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    }
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> obtenerMiCobertura() async {
    final res = await _gatewayClient.get('/api/v1/core/profiles/me/coverage');
    final data = res['data'] ?? res['cobertura'];
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    }
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> declararCobertura(
    List<String> zonaIds,
  ) async {
    final res = await _gatewayClient.post(
      '/api/v1/core/profiles/me/coverage',
      body: {'zona_ids': zonaIds},
    );
    final data = res['data'] ?? res['cobertura'];
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    }
    return const [];
  }

  @override
  String? get tenantIdSesion =>
      _client.auth.currentUser?.appMetadata['tenant_id'] as String?;
}
