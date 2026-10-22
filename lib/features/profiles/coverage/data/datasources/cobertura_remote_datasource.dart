import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso crudo a Supabase. La app llama a Supabase directamente con el SDK
/// (no hay backend intermedio). `tenant_id` y `aliado_id` NUNCA se envían:
/// la RPC los toma del JWT (anti tenant-spoofing, DDL_MANI §estrategia).
abstract interface class CoberturaRemoteDataSource {
  Future<List<Map<String, dynamic>>> listarZonas(String? padreId);
  Future<List<Map<String, dynamic>>> buscarZonas(String ciudadId, String texto);
  Future<List<Map<String, dynamic>>> obtenerMiCobertura();
  Future<List<Map<String, dynamic>>> declararCobertura(List<String> zonaIds);

  /// Solo para trazas (log estructurado); nunca se usa para autorizar.
  String? get tenantIdSesion;
}

class SupabaseCoberturaDataSource implements CoberturaRemoteDataSource {
  SupabaseCoberturaDataSource(this._client);

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> _rpc(
    String fn, [
    Map<String, dynamic>? params,
  ]) async {
    final res = await _client.rpc(fn, params: params);
    if (res is! List) return const [];
    return res
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listarZonas(String? padreId) =>
      _rpc('listar_zonas', {'p_padre_id': padreId});

  @override
  Future<List<Map<String, dynamic>>> buscarZonas(
    String ciudadId,
    String texto,
  ) => _rpc('buscar_zonas', {'p_ciudad_id': ciudadId, 'p_texto': texto});

  @override
  Future<List<Map<String, dynamic>>> obtenerMiCobertura() =>
      _rpc('obtener_mi_cobertura');

  @override
  Future<List<Map<String, dynamic>>> declararCobertura(List<String> zonaIds) =>
      _rpc('declarar_cobertura', {'p_zona_ids': zonaIds});

  @override
  String? get tenantIdSesion =>
      _client.auth.currentUser?.appMetadata['tenant_id'] as String?;
}
