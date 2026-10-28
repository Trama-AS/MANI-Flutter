import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso crudo a la bandeja de verificación. `tenant_id` NUNCA se envía: el
/// servidor lo deriva de la sesión (claim del JWT en Core, `auth.uid()` en las
/// RPC de la migración 002_verificacion_aliados.sql).
abstract interface class VerificacionRemoteDataSource {
  Future<List<Map<String, dynamic>>> listarAliados();
  Future<Map<String, dynamic>> obtenerAliado(String aliadoId);
  Future<Map<String, dynamic>> resolver(
    String aliadoId,
    String decision,
    String? motivo,
  );

  /// URL firmada de vida corta. Core la emite por [aliadoId] y [documentoId];
  /// [rutaStorage] se conserva para los dobles de prueba.
  Future<String> urlFirmada(
    String rutaStorage, {
    String? aliadoId,
    String? documentoId,
  });

  /// Solo para trazas (log estructurado); nunca se usa para autorizar.
  String? get tenantIdSesion;
}

/// Todas las operaciones salen por el API Gateway hacia Core Node
/// (`/api/v1/core/aliados/...`); ninguna llama RPC, tablas ni Storage de
/// Supabase (ADR-0027). Supabase solo se usa para leer la sesión local.
class GatewayVerificacionDataSource implements VerificacionRemoteDataSource {
  GatewayVerificacionDataSource(this._gateway, {SupabaseClient? sesion})
    : _sesion = sesion;

  static const _rutaAliados = '/api/v1/core/aliados';

  final GatewayClient _gateway;
  final SupabaseClient? _sesion;

  @override
  Future<List<Map<String, dynamic>>> listarAliados() async {
    // Core responde un arreglo; GatewayClient lo envuelve en `data`.
    final lista = (await _gateway.get('$_rutaAliados/verificacion'))['data'];
    if (lista is! List) {
      throw _respuestaInesperada;
    }
    return lista
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> obtenerAliado(String aliadoId) => _gateway.get(
    '$_rutaAliados/${Uri.encodeComponent(aliadoId)}/verificacion',
  );

  @override
  Future<Map<String, dynamic>> resolver(
    String aliadoId,
    String decision,
    String? motivo,
  ) => _gateway.patch(
    '$_rutaAliados/${Uri.encodeComponent(aliadoId)}/verificacion',
    {'decision': decision, 'motivo': ?motivo},
  );

  @override
  Future<String> urlFirmada(
    String rutaStorage, {
    String? aliadoId,
    String? documentoId,
  }) async {
    if (aliadoId == null || documentoId == null) {
      throw const GatewayException(
        message: 'Documento sin aliado o identificador',
        statusCode: 404,
      );
    }
    final res = await _gateway.get(
      '$_rutaAliados/${Uri.encodeComponent(aliadoId)}'
      '/documentos/${Uri.encodeComponent(documentoId)}/url',
    );
    final url = res['url'] ?? res['signedUrl'];
    if (url is! String || url.isEmpty) {
      throw _respuestaInesperada;
    }
    return url;
  }

  @override
  String? get tenantIdSesion {
    final user = _sesion?.auth.currentUser;
    return (user?.appMetadata['tenant_id'] ?? user?.userMetadata?['tenant_id'])
        as String?;
  }

  static const _respuestaInesperada = GatewayException(
    message: 'Respuesta inesperada del servidor',
    statusCode: 502,
  );
}
