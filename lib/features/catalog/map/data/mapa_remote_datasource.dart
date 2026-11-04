import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/catalog/map/domain/entities/geometria_zona.dart';

/// Resultado de pedir los límites de un conjunto de zonas.
///
/// Conserva las tres situaciones que distingue el contrato, porque el criterio
/// C2 exige mostrarlas y no inventar coordenadas: con geometría, sin geometría
/// cargada, y zona desconocida.
class GeometriasZonas {
  const GeometriasZonas({
    required this.geometrias,
    required this.sinGeometria,
    required this.desconocidas,
    required this.atribuciones,
  });

  final List<GeometriaZona> geometrias;
  final List<String> sinGeometria;
  final List<String> desconocidas;
  final List<String> atribuciones;
}

/// Sede del cliente con su ubicación declarada, si la tiene.
class SitioUbicado {
  const SitioUbicado({
    required this.id,
    required this.nombre,
    required this.zonaId,
    this.latitud,
    this.longitud,
  });

  final String id;
  final String nombre;
  final String zonaId;

  /// `null` cuando la sede no tiene punto capturado. No se completa con el
  /// centroide de su zona ni con la dirección: se informa que falta (C2).
  final double? latitud;
  final double? longitud;

  bool get tieneCoordenadas => latitud != null && longitud != null;
}

abstract interface class MapaRemoteDataSource {
  /// Catálogo jerárquico: `id`, `nombre`, `nivel`, `parentId`, `selectable`.
  Future<List<Map<String, dynamic>>> listarZonas();

  Future<GeometriasZonas> obtenerGeometrias(List<String> zonaIds);

  /// Sedes del cliente de la sesión. Solo el rol cliente las obtiene: para un
  /// admin el servicio responde error, y el mapa debe seguir funcionando con
  /// las zonas, sin sedes.
  Future<List<SitioUbicado>> listarMisSitios();

  /// Zonas que el aliado de la sesión declaró como cobertura. Solo el rol
  /// aliado las obtiene. **Es lectura:** la cobertura se declara por lista en
  /// `/aliado/cobertura` y hasta localidad (decisión del 04-nov-2026); este
  /// mapa la muestra, no la modifica.
  Future<List<String>> listarMiCobertura();
}

/// Todo sale por el API Gateway hacia Core Node; no hay llamada directa a
/// Supabase ni a los puertos internos de los servicios (ADR-0027, CLAUDE.md §1).
class GatewayMapaDataSource implements MapaRemoteDataSource {
  GatewayMapaDataSource(this._gateway);

  static const _rutaZonas = '/api/v1/core/catalog/zones';
  static const _rutaGeometrias = '/api/v1/core/catalog/geometrias';
  static const _rutaSitios = '/api/v1/core/solicitudes/sitios';
  static const _rutaCobertura = '/api/v1/core/profiles/me/coverage';

  /// Mismo tope que impone Core: pedir más devuelve 400.
  static const maxZonasPorPeticion = 20;

  final GatewayClient _gateway;

  @override
  Future<List<Map<String, dynamic>>> listarZonas() async {
    final res = await _gateway.get(_rutaZonas);
    final zonas = res['zones'];
    if (zonas is! List) return const [];
    return zonas.whereType<Map>().map((z) => Map<String, dynamic>.from(z)).toList(growable: false);
  }

  @override
  Future<GeometriasZonas> obtenerGeometrias(List<String> zonaIds) async {
    if (zonaIds.isEmpty) {
      return const GeometriasZonas(
        geometrias: [],
        sinGeometria: [],
        desconocidas: [],
        atribuciones: [],
      );
    }
    final res = await _gateway.get(
      _rutaGeometrias,
      queryParameters: {'zonaIds': zonaIds.take(maxZonasPorPeticion).join(',')},
    );
    return parsear(res);
  }

  @override
  Future<List<SitioUbicado>> listarMisSitios() async {
    final res = await _gateway.get(_rutaSitios);
    return parsearSitios(res);
  }

  @override
  Future<List<String>> listarMiCobertura() async {
    final res = await _gateway.get(_rutaCobertura);
    return parsearCobertura(res);
  }

  /// Separado del transporte para poder probar el parseo sin red.
  static List<String> parsearCobertura(Map<String, dynamic> res) {
    final ids = res['zoneIds'];
    if (ids is! List) return const [];
    return ids.map((v) => '$v').where((s) => s.isNotEmpty).toList(growable: false);
  }

  /// Separado del transporte para poder probar el parseo sin red.
  static List<SitioUbicado> parsearSitios(Map<String, dynamic> res) {
    final sitios = res['sitios'];
    if (sitios is! List) return const [];
    return sitios.whereType<Map>().map((s) {
      return SitioUbicado(
        id: '${s['id'] ?? ''}',
        nombre: '${s['nombre'] ?? ''}',
        zonaId: '${s['zonaId'] ?? ''}',
        latitud: _comoDouble(s['latitud']),
        longitud: _comoDouble(s['longitud']),
      );
    }).toList(growable: false);
  }

  /// Un valor ausente o no numérico es ausencia de punto, nunca cero: el
  /// ecuador no es una ubicación por omisión.
  static double? _comoDouble(Object? valor) {
    if (valor is num) return valor.toDouble();
    if (valor is String) return double.tryParse(valor);
    return null;
  }

  /// Separado del transporte para poder probar el parseo sin red.
  static GeometriasZonas parsear(Map<String, dynamic> res) {
    final features = res['features'];
    final geometrias = <GeometriaZona>[];
    if (features is List) {
      for (final f in features.whereType<Map>()) {
        final props = f['properties'];
        if (props is! Map) continue;
        final anillos = GeometriaZona.anillosDesdeGeoJson(f['geometry']);
        geometrias.add(
          GeometriaZona(
            zonaId: '${props['zoneId'] ?? f['id'] ?? ''}',
            nombre: '${props['name'] ?? ''}',
            nivel: '${props['level'] ?? ''}',
            anillos: anillos,
            atribucion: '${props['attribution'] ?? ''}',
          ),
        );
      }
    }
    return GeometriasZonas(
      geometrias: geometrias,
      sinGeometria: _textos(res['sinGeometria']),
      desconocidas: _textos(res['desconocidas']),
      atribuciones: _textos(res['atribuciones']),
    );
  }

  static List<String> _textos(Object? valor) {
    if (valor is! List) return const [];
    return valor.map((v) => '$v').toList(growable: false);
  }
}
