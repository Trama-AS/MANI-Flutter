import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mani/core/network/gateway_client.dart';

import '../../domain/entities/foto_adjunta.dart';

/// Acceso remoto de US-04.1.1. Ni `tenant_id` ni `cliente_id` viajan desde la
/// app: Core los toma del JWT.
///
/// La creación va por el API Gateway a Core (`POST /api/v1/core/solicitudes`,
/// SCRUM-1072, ADR-0027): Core valida, sube las fotos al bucket `solicitudes` y
/// crea la solicitud en una transacción. Los catálogos (categorías, sitios y
/// zonas) siguen en las RPC de la migración 006 hasta que Core exponga sus
/// endpoints.
abstract interface class SolicitudesClienteRemoteDataSource {
  Future<List<Map<String, dynamic>>> listarCategorias();
  Future<List<Map<String, dynamic>>> listarSitios();
  Future<List<Map<String, dynamic>>> buscarZonas(String texto);

  /// Publica la solicitud con sus fotos en una sola petición multipart.
  /// Devuelve el objeto `solicitud` de la respuesta de Core.
  Future<Map<String, dynamic>> crear({
    required String categoriaId,
    required String descripcion,
    required List<FotoAdjunta> fotos,
    required String claveIdempotencia,
    String? sitioId,
    String? direccion,
    String? zonaId,
  });

  /// Pide a Dispatch que ofrezca la solicitud a los aliados elegibles
  /// (broadcast, SCRUM-1402). Dispatch no duplica la oferta a un mismo aliado,
  /// así que repetirlo es seguro.
  Future<void> avisarAliados(String solicitudId, {required String clave});

  /// `null` sin sesión; evita enviar la petición sin JWT.
  String? get usuarioId;

  /// Solo para trazas (log estructurado); nunca se usa para autorizar.
  String? get tenantIdSesion;
}

class SolicitudesClienteRemoteDataSourceImpl
    implements SolicitudesClienteRemoteDataSource {
  SolicitudesClienteRemoteDataSourceImpl(this._client, this._gateway);

  static const rutaCrear = '/api/v1/core/solicitudes';
  static const rutaOrquestar = '/api/v1/dispatch/requests/orchestrate';

  final SupabaseClient _client;
  final GatewayClient _gateway;

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
  Future<Map<String, dynamic>> crear({
    required String categoriaId,
    required String descripcion,
    required List<FotoAdjunta> fotos,
    required String claveIdempotencia,
    String? sitioId,
    String? direccion,
    String? zonaId,
  }) async {
    final respuesta = await _gateway.postMultipart(
      rutaCrear,
      campos: {
        'categoriaId': categoriaId,
        'descripcion': descripcion,
        'claveIdempotencia': claveIdempotencia,
        'sitioId': ?sitioId,
        'direccion': ?direccion,
        'zonaId': ?zonaId,
      },
      archivos: [
        for (var i = 0; i < fotos.length; i++)
          ArchivoMultipart(
            campo: 'fotos',
            nombre: '${i + 1}.${fotos[i].extension}',
            bytes: fotos[i].bytes,
            tipoContenido: fotos[i].mime,
          ),
      ],
      // Core es idempotente por claveIdempotencia: el GatewayClient puede
      // reintentar ante red caída o 502/503/504 sin duplicar la solicitud.
      headers: {GatewayClient.headerIdempotencyKey: claveIdempotencia},
    );
    final solicitud = respuesta['solicitud'];
    if (solicitud is Map) {
      return Map<String, dynamic>.from(solicitud);
    }
    throw const FormatException('Respuesta inesperada de Core');
  }

  /// El cliente y el tenant salen del JWT; el cuerpo solo lleva la solicitud.
  /// La clave permite que el `GatewayClient` reintente ante 502/503/504.
  @override
  Future<void> avisarAliados(String solicitudId, {required String clave}) =>
      _gateway.postJson(
        rutaOrquestar,
        {'requestId': solicitudId},
        headers: {GatewayClient.headerIdempotencyKey: clave},
      );

  @override
  String? get usuarioId => _client.auth.currentUser?.id;

  @override
  String? get tenantIdSesion {
    final user = _client.auth.currentUser;
    return (user?.appMetadata['tenant_id'] ?? user?.userMetadata?['tenant_id'])
        as String?;
  }
}
