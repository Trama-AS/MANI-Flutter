import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso crudo a Supabase. `tenant_id` NUNCA se envía: las RPC lo derivan
/// de `auth.uid()` (migración 003_categorias_servicio.sql).
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
  SupabaseCategoriasDataSource(this._client);

  final SupabaseClient _client;

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
  String? get tenantIdSesion {
    final user = _client.auth.currentUser;
    return (user?.appMetadata['tenant_id'] ?? user?.userMetadata?['tenant_id'])
        as String?;
  }
}
