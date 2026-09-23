import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso crudo a Supabase (RPC de la migración 006 y Storage). Ni
/// `tenant_id` ni `cliente_id` viajan desde la app: salen de `auth.uid()`.
abstract interface class SolicitudesClienteRemoteDataSource {
  Future<List<Map<String, dynamic>>> listarCategorias();
  Future<List<Map<String, dynamic>>> listarSitios();
  Future<List<Map<String, dynamic>>> buscarZonas(String texto);

  /// Sube (o reemplaza) un archivo en el bucket privado de solicitudes.
  Future<void> subirFoto(String ruta, Uint8List bytes, String mime);
  Future<void> eliminarFotos(List<String> rutas);

  Future<Map<String, dynamic>> crear({
    required String categoriaId,
    required String descripcion,
    required List<String> fotos,
    required String claveIdempotencia,
    String? sitioId,
    String? direccion,
    String? zonaId,
  });

  /// Carpeta del usuario en Storage (`auth.uid()`); `null` sin sesión.
  String? get usuarioId;

  /// Solo para trazas (log estructurado); nunca se usa para autorizar.
  String? get tenantIdSesion;
}

class SupabaseSolicitudesClienteDataSource
    implements SolicitudesClienteRemoteDataSource {
  SupabaseSolicitudesClienteDataSource(
    this._client, {
    this.bucket = 'solicitudes',
  });

  final SupabaseClient _client;
  final String bucket;

  Future<List<Map<String, dynamic>>> _lista(
    String fn, [
    Map<String, dynamic>? params,
  ]) async {
    final res = await _client.rpc(fn, params: params);
    if (res is! List) {
      return const [];
    }
    return res
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listarCategorias() =>
      _lista('listar_categorias_cliente');

  @override
  Future<List<Map<String, dynamic>>> listarSitios() =>
      _lista('listar_mis_sitios');

  @override
  Future<List<Map<String, dynamic>>> buscarZonas(String texto) =>
      _lista('buscar_zonas_cliente', {'p_texto': texto});

  @override
  Future<void> subirFoto(String ruta, Uint8List bytes, String mime) => _client
      .storage
      .from(bucket)
      .uploadBinary(
        ruta,
        bytes,
        fileOptions: FileOptions(contentType: mime, upsert: true),
      );

  @override
  Future<void> eliminarFotos(List<String> rutas) =>
      _client.storage.from(bucket).remove(rutas);

  @override
  Future<Map<String, dynamic>> crear({
    required String categoriaId,
    required String descripcion,
    required List<String> fotos,
    required String claveIdempotencia,
    String? sitioId,
    String? direccion,
    String? zonaId,
  }) async {
    final res = await _client.rpc(
      'crear_solicitud',
      params: {
        'p_categoria_id': categoriaId,
        'p_descripcion': descripcion,
        'p_sitio_id': sitioId,
        'p_direccion': direccion,
        'p_zona_id': zonaId,
        'p_fotos': fotos,
        'p_clave_idempotencia': claveIdempotencia,
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
  String? get usuarioId => _client.auth.currentUser?.id;

  @override
  String? get tenantIdSesion {
    final user = _client.auth.currentUser;
    return (user?.appMetadata['tenant_id'] ?? user?.userMetadata?['tenant_id'])
        as String?;
  }
}
