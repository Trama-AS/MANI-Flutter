import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mani/core/network/api_gateway_client.dart';

/// Acceso a servicios de verificación de aliados a través del API Gateway (ADR-0019 / ADR-0027).
abstract interface class VerificacionRemoteDataSource {
  Future<List<Map<String, dynamic>>> listarAliados();
  Future<Map<String, dynamic>> obtenerAliado(String aliadoId);
  Future<Map<String, dynamic>> resolver(
    String aliadoId,
    String decision,
    String? motivo,
  );
  Future<String> urlFirmada(String rutaStorage);

  /// Solo para trazas (log estructurado); nunca se usa para autorizar.
  String? get tenantIdSesion;
}

class SupabaseVerificacionDataSource implements VerificacionRemoteDataSource {
  SupabaseVerificacionDataSource(
    this._client, {
    this.bucket = 'kyc',
    this.vigenciaUrl = const Duration(minutes: 5),
    ApiGatewayClient? gatewayClient,
  }) : _gatewayClient = gatewayClient ?? ApiGatewayClient();

  final SupabaseClient _client;
  final String bucket;
  final Duration vigenciaUrl;
  final ApiGatewayClient _gatewayClient;

  @override
  Future<List<Map<String, dynamic>>> listarAliados() async {
    final res = await _gatewayClient.get('/api/v1/core/verification/allies');
    final data = res['data'] ?? res['aliados'];
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    }
    return const [];
  }

  @override
  Future<Map<String, dynamic>> obtenerAliado(String aliadoId) async {
    final res = await _gatewayClient.get(
      '/api/v1/core/verification/allies/$aliadoId',
    );
    if (res['data'] is Map) {
      return Map<String, dynamic>.from(res['data'] as Map);
    }
    return res;
  }

  @override
  Future<Map<String, dynamic>> resolver(
    String aliadoId,
    String decision,
    String? motivo,
  ) async {
    final res = await _gatewayClient.post(
      '/api/v1/core/verification/allies/$aliadoId/resolve',
      body: {'decision': decision, 'motivo': motivo},
    );
    if (res['data'] is Map) {
      return Map<String, dynamic>.from(res['data'] as Map);
    }
    return res;
  }

  @override
  Future<String> urlFirmada(String rutaStorage) async {
    final res = await _gatewayClient.post(
      '/api/v1/core/storage/signed-url',
      body: {
        'path': rutaStorage,
        'bucket': bucket,
        'expiresIn': vigenciaUrl.inSeconds,
      },
    );
    return res['signedUrl']?.toString() ??
        res['url']?.toString() ??
        rutaStorage;
  }

  @override
  String? get tenantIdSesion {
    final user = _client.auth.currentUser;
    return (user?.appMetadata['tenant_id'] ?? user?.userMetadata?['tenant_id'])
        as String?;
  }
}
