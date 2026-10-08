import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mani/core/network/api_gateway_client.dart';

/// Acceso a servicios de despacho a través del API Gateway (ADR-0019 / ADR-0027).
abstract interface class AsignacionRemoteDataSource {
  Future<List<Map<String, dynamic>>> listar();
  Future<Map<String, dynamic>> aceptar(String solicitudId);
  Future<void> rechazar(String solicitudId, String? motivo);

  /// Solo para trazas (log estructurado); nunca se usa para autorizar.
  String? get tenantIdSesion;
}

class SupabaseAsignacionDataSource implements AsignacionRemoteDataSource {
  SupabaseAsignacionDataSource(this._client, {ApiGatewayClient? gatewayClient})
    : _gatewayClient = gatewayClient ?? ApiGatewayClient();

  final SupabaseClient _client;
  final ApiGatewayClient _gatewayClient;

  @override
  Future<List<Map<String, dynamic>>> listar() async {
    final res = await _gatewayClient.get('/api/v1/dispatch/requests');
    final data = res['data'] ?? res['requests'] ?? res['solicitudes'];
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    }
    return const [];
  }

  @override
  Future<Map<String, dynamic>> aceptar(String solicitudId) async {
    final res = await _gatewayClient.post(
      '/api/v1/dispatch/requests/$solicitudId/accept',
    );
    return res;
  }

  @override
  Future<void> rechazar(String solicitudId, String? motivo) async {
    await _gatewayClient.post(
      '/api/v1/dispatch/requests/$solicitudId/reject',
      body: {'motivo': motivo},
    );
  }

  @override
  String? get tenantIdSesion {
    final user = _client.auth.currentUser;
    return (user?.appMetadata['tenant_id'] ?? user?.userMetadata?['tenant_id'])
        as String?;
  }
}
