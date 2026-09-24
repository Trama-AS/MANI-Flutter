import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso crudo a Supabase. Ni `tenant_id` ni `aliado_id` viajan desde la
/// app: las RPC los derivan de `auth.uid()`
/// (migración 005_aceptar_rechazar_solicitud.sql).
abstract interface class AsignacionRemoteDataSource {
  Future<List<Map<String, dynamic>>> listar();
  Future<Map<String, dynamic>> aceptar(String solicitudId);
  Future<void> rechazar(String solicitudId, String? motivo);

  /// Solo para trazas (log estructurado); nunca se usa para autorizar.
  String? get tenantIdSesion;
}

class SupabaseAsignacionDataSource implements AsignacionRemoteDataSource {
  SupabaseAsignacionDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> listar() async {
    final res = await _client.rpc('listar_solicitudes_aliado');
    if (res is! List) {
      return const [];
    }
    return res
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> aceptar(String solicitudId) async {
    final res = await _client.rpc(
      'aceptar_solicitud',
      params: {'p_solicitud_id': solicitudId},
    );
    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    throw const PostgrestException(
      message: 'Respuesta inesperada del servidor',
    );
  }

  @override
  Future<void> rechazar(String solicitudId, String? motivo) => _client.rpc(
    'rechazar_solicitud',
    params: {'p_solicitud_id': solicitudId, 'p_motivo': motivo},
  );

  @override
  String? get tenantIdSesion {
    final user = _client.auth.currentUser;
    return (user?.appMetadata['tenant_id'] ?? user?.userMetadata?['tenant_id'])
        as String?;
  }
}
