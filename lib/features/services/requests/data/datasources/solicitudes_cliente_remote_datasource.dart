import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mani/core/network/api_gateway_client.dart';

/// Acceso a servicios de solicitudes a través del API Gateway (ADR-0019 / ADR-0027).
abstract interface class SolicitudesClienteRemoteDataSource {
  Future<List<Map<String, dynamic>>> listarCategorias();
  Future<List<Map<String, dynamic>>> listarSitios();
  Future<List<Map<String, dynamic>>> buscarZonas(String texto);

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

  String? get usuarioId;
  String? get tenantIdSesion;
}

class SupabaseSolicitudesClienteDataSource
    implements SolicitudesClienteRemoteDataSource {
  SupabaseSolicitudesClienteDataSource(
    this._client, {
    this.bucket = 'solicitudes',
    ApiGatewayClient? gatewayClient,
  }) : _gatewayClient = gatewayClient ?? ApiGatewayClient();

  final SupabaseClient _client;
  final String bucket;
  final ApiGatewayClient _gatewayClient;

  @override
  Future<List<Map<String, dynamic>>> listarCategorias() async {
    final res = await _gatewayClient.get('/api/v1/core/catalog/categories');
    final data = res['data'] ?? res['categories'] ?? res['categorias'];
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    }
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> listarSitios() async {
    final res = await _gatewayClient.get('/api/v1/core/sites');
    final data = res['data'] ?? res['sitios'];
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    }
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> buscarZonas(String texto) async {
    final res = await _gatewayClient.get('/api/v1/core/zones/search?q=$texto');
    final data = res['data'] ?? res['zonas'];
    if (data is List) {
      return data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    }
    return const [];
  }

  @override
  Future<void> subirFoto(String ruta, Uint8List bytes, String mime) async {
    await _gatewayClient.post(
      '/api/v1/core/storage/upload',
      body: {
        'bucket': bucket,
        'path': ruta,
        'bytes': base64Encode(bytes),
        'mime': mime,
      },
    );
  }

  @override
  Future<void> eliminarFotos(List<String> rutas) async {
    await _gatewayClient.post(
      '/api/v1/core/storage/remove',
      body: {'bucket': bucket, 'paths': rutas},
    );
  }

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
    final res = await _gatewayClient.post(
      '/api/v1/core/requests',
      body: {
        'categoria_id': categoriaId,
        'descripcion': descripcion,
        'fotos': fotos,
        'clave_idempotencia': claveIdempotencia,
        'sitio_id': ?sitioId,
        'direccion': ?direccion,
        'zona_id': ?zonaId,
      },
    );
    if (res['data'] is Map) {
      return Map<String, dynamic>.from(res['data'] as Map);
    }
    return res;
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
