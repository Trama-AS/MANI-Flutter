import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class IRecuperacionContrasenaRemoteDataSource {
  Future<void> solicitar({required String email, required String tenantSlug});

  Future<void> restablecer({
    required String accessToken,
    required String newPassword,
    required String tenantSlug,
  });
}

/// Recuperación de contraseña (HU-M02-10) a través del Gateway hacia Core.
/// Core orquesta el proveedor de identidad; el cliente no habla con
/// Supabase salvo para cerrar la sesión de recuperación que él mismo abre.
class RecuperacionContrasenaRemoteDataSource
    implements IRecuperacionContrasenaRemoteDataSource {
  RecuperacionContrasenaRemoteDataSource({
    required this.client,
    required this.gateway,
  });

  final SupabaseClient client;
  final GatewayClient gateway;

  static const rutaSolicitud = '/api/v1/core/auth/password-recovery';
  static const rutaRestablecimiento = '/api/v1/core/auth/password-reset';

  /// El tenant va solo en `X-Tenant-Slug` (ADR-0018), nunca en el cuerpo.
  static const headerTenantSlug = 'X-Tenant-Slug';

  static const mensajeEnlaceInvalido =
      'El enlace de recuperación no es válido o ya venció. Solicita uno nuevo.';
  static const mensajeDemasiadosEnvios =
      'Se enviaron demasiados correos de recuperación. Inténtalo más tarde.';

  @override
  Future<void> solicitar({
    required String email,
    required String tenantSlug,
  }) async {
    try {
      await gateway.postJson(
        rutaSolicitud,
        {'email': email.trim()},
        headers: {headerTenantSlug: tenantSlug},
      );
    } on GatewayException catch (e) {
      throw _traducir(e);
    }
  }

  @override
  Future<void> restablecer({
    required String accessToken,
    required String newPassword,
    required String tenantSlug,
  }) async {
    try {
      await gateway.postJson(
        rutaRestablecimiento,
        {'accessToken': accessToken, 'newPassword': newPassword},
        headers: {headerTenantSlug: tenantSlug},
      );
    } on GatewayException catch (e) {
      throw _traducir(e);
    }
    // Al abrir el enlace, el SDK puede haber iniciado una sesión de
    // recuperación: se cierra para que la persona entre con su contraseña nueva.
    try {
      await client.auth.signOut();
    } catch (_) {}
  }

  /// El 401 de estas rutas es un enlace inválido, no una sesión vencida.
  GatewayException _traducir(GatewayException e) {
    if (e.isUnauthorized) {
      return GatewayException(
        message: mensajeEnlaceInvalido,
        statusCode: e.statusCode,
        correlationId: e.correlationId,
        cuerpo: e.cuerpo,
      );
    }
    if (e.statusCode == 429) {
      return GatewayException(
        message: mensajeDemasiadosEnvios,
        statusCode: e.statusCode,
        correlationId: e.correlationId,
        cuerpo: e.cuerpo,
      );
    }
    return e;
  }
}
