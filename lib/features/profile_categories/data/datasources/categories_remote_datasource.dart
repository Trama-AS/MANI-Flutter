import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso crudo a Supabase. `tenant_id` y `aliado_id` NUNCA se envían: las
/// RPC los toman de `auth.uid()` (migración 003_aliado_categorias.sql).
abstract interface class CategoriesRemoteDataSource {
  Future<List<Map<String, dynamic>>> listarCategoriasTenant();
  Future<List<String>> obtenerMisCategorias();
  Future<List<String>> guardarMisCategorias(List<String> categoriaIds);
}

class SupabaseCategoriesDataSource implements CategoriesRemoteDataSource {
  SupabaseCategoriesDataSource(this._client);

  final SupabaseClient _client;

  Future<List<dynamic>> _rpc(String fn, [Map<String, dynamic>? params]) async {
    final res = await _client.rpc(fn, params: params);
    return res is List ? res : const [];
  }

  @override
  Future<List<Map<String, dynamic>>> listarCategoriasTenant() async =>
      (await _rpc('listar_categorias_tenant'))
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);

  @override
  Future<List<String>> obtenerMisCategorias() async =>
      (await _rpc('obtener_mis_categorias')).cast<String>();

  @override
  Future<List<String>> guardarMisCategorias(List<String> categoriaIds) async =>
      (await _rpc('guardar_mis_categorias', {
        'p_categoria_ids': categoriaIds,
      })).cast<String>();
}
