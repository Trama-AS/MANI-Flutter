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

abstract interface class MapaRemoteDataSource {
  /// Catálogo jerárquico: `id`, `nombre`, `nivel`, `parentId`, `selectable`.
  Future<List<Map<String, dynamic>>> listarZonas();

  Future<GeometriasZonas> obtenerGeometrias(List<String> zonaIds);
}

/// Todo sale por el API Gateway hacia Core Node; no hay llamada directa a
/// Supabase ni a los puertos internos de los servicios (ADR-0027, CLAUDE.md §1).
class GatewayMapaDataSource implements MapaRemoteDataSource {
  GatewayMapaDataSource(this._gateway);

  static const _rutaZonas = '/api/v1/core/catalog/zones';
  static const _rutaGeometrias = '/api/v1/core/catalog/geometrias';

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
