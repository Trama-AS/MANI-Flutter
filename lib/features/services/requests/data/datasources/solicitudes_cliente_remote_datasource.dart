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
/// SCRUM-1465), igual que la búsqueda de zonas, que lee el catálogo de Core
/// (`GET /api/v1/core/catalog/zones`, SCRUM-1393) en lugar de la RPC
/// `buscar_zonas_cliente`.
abstract interface class SolicitudesClienteRemoteDataSource {
  Future<List<Map<String, dynamic>>> listarCategorias();
  Future<List<Map<String, dynamic>>> listarSitios();

  /// Zonas escogibles con [texto] en el nombre, con las mismas reglas que la
  /// RPC `buscar_zonas_cliente`: solo zonas activas con zona padre (barrios y
  /// localidades, no ciudades), sin distinguir mayúsculas, desde 2 caracteres,
  /// ordenadas por nombre y como máximo 20. Cada mapa trae `id`, `nombre` y
  /// `zonaPadre`.
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
  SolicitudesClienteRemoteDataSourceImpl(
    this._client,
    this._gateway, {
    DateTime Function()? ahora,
  }) : _ahora = ahora ?? DateTime.now;

  static const rutaCrear = '/api/v1/core/solicitudes';
  static const rutaCategorias = '/api/v1/core/solicitudes/categorias';
  static const rutaSitios = '/api/v1/core/solicitudes/sitios';
  static const rutaZonas = '/api/v1/core/catalog/zones';
  static const rutaOrquestar = '/api/v1/dispatch/requests/orchestrate';

  /// El catálogo de zonas es global y cambia poco: se relee cada 5 minutos en
  /// vez de en cada búsqueda mientras el cliente escribe.
  static const vigenciaCatalogoZonas = Duration(minutes: 5);
  static const minimoBusquedaZonas = 2;
  static const maximoZonas = 20;

  final SupabaseClient _client;
  final GatewayClient _gateway;
  final DateTime Function() _ahora;

  List<Map<String, dynamic>>? _catalogoZonas;
  DateTime? _catalogoLeidoEn;

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

  /// Catálogo completo, también con las zonas inactivas (`selectable: false`):
  /// así una zona activa conserva el nombre de su padre aunque el padre esté
  /// inactivo, como hacía el `LEFT JOIN` de la RPC. Un error no se guarda.
  Future<List<Map<String, dynamic>>> _catalogo() async {
    final ahora = _ahora();
    final guardado = _catalogoZonas;
    final leidoEn = _catalogoLeidoEn;
    if (guardado != null &&
        leidoEn != null &&
        ahora.difference(leidoEn) < vigenciaCatalogoZonas) {
      return guardado;
    }
    final zonas = await _listaCore(rutaZonas, 'zones');
    _catalogoZonas = zonas;
    _catalogoLeidoEn = ahora;
    return zonas;
  }

  @override
  Future<List<Map<String, dynamic>>> buscarZonas(String texto) async {
    final buscado = texto.trim().toLowerCase();
    if (buscado.length < minimoBusquedaZonas) {
      return const [];
    }
    final catalogo = await _catalogo();
    final nombres = {for (final z in catalogo) z['id']: z['name']};
    final encontradas =
        catalogo
            .where(
              (z) =>
                  z['parentId'] != null &&
                  z['selectable'] == true &&
                  (z['name'] as String? ?? '').toLowerCase().contains(buscado),
            )
            .map(
              (z) => <String, dynamic>{
                'id': z['id'],
                'nombre': z['name'],
                'zonaPadre': nombres[z['parentId']],
              },
            )
            .toList()
          ..sort(
            (a, b) => (a['nombre'] as String).compareTo(b['nombre'] as String),
          );
    return encontradas.take(maximoZonas).toList(growable: false);
  }

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
