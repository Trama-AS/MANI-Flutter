import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mani/core/network/gateway_client.dart';

import '../../domain/entities/foto_adjunta.dart';

/// Acceso remoto de US-04.1.1. Ni `tenant_id` ni `cliente_id` viajan desde la
/// app: Core los toma del JWT.
///
/// La creación va por el API Gateway a Core (`POST /api/v1/core/solicitudes`,
/// SCRUM-1072, ADR-0027): Core valida, sube las fotos al bucket `solicitudes` y
/// crea la solicitud en una transacción. Las categorías y los sitios también
/// van por Core (`GET /api/v1/core/solicitudes/categorias` y `/sitios`,
/// SCRUM-1465). La búsqueda de zonas sigue en la RPC `buscar_zonas_cliente`
/// hasta que Core exponga el catálogo de zonas (SCRUM-1393).
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

  /// `null` sin sesión; evita enviar la petición sin JWT.
  String? get usuarioId;

  /// Solo para trazas (log estructurado); nunca se usa para autorizar.
  String? get tenantIdSesion;
}

class SolicitudesClienteRemoteDataSourceImpl
    implements SolicitudesClienteRemoteDataSource {
  SolicitudesClienteRemoteDataSourceImpl(this._client, this._gateway);

  static const rutaCrear = '/api/v1/core/solicitudes';
  static const rutaCategorias = '/api/v1/core/solicitudes/categorias';
  static const rutaSitios = '/api/v1/core/solicitudes/sitios';

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

  /// Lee la lista [campo] de una respuesta de Core; sin lista no inventa datos.
  Future<List<Map<String, dynamic>>> _listaCore(
    String ruta,
    String campo,
  ) async {
    final respuesta = await _gateway.get(ruta);
    final lista = respuesta[campo];
    if (lista is! List) {
      throw FormatException('Respuesta de Core sin "$campo"');
    }
    return lista
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listarCategorias() =>
      _listaCore(rutaCategorias, 'categorias');

  @override
  Future<List<Map<String, dynamic>>> listarSitios() =>
      _listaCore(rutaSitios, 'sitios');

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

  @override
  String? get usuarioId => _client.auth.currentUser?.id;

  @override
  String? get tenantIdSesion {
    final user = _client.auth.currentUser;
    return (user?.appMetadata['tenant_id'] ?? user?.userMetadata?['tenant_id'])
        as String?;
  }
}
