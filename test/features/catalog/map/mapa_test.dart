import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/catalog/map/data/mapa_remote_datasource.dart';
import 'package:mani/features/catalog/map/domain/entities/geometria_zona.dart';
import 'package:mani/features/catalog/map/presentation/bloc/mapa_cubit.dart';

const _chapinero = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a13';
const _chico = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a15';

/// Recorte real de Chicó Norte tal como lo entrega el contrato: GeoJSON con
/// las coordenadas en orden longitud, latitud.
Map<String, dynamic> _respuesta({List<String> sinGeometria = const []}) => {
  'type': 'FeatureCollection',
  'features': [
    {
      'type': 'Feature',
      'id': _chico,
      'geometry': {
        'type': 'Polygon',
        'coordinates': [
          [
            [-74.05045, 4.68132],
            [-74.04500, 4.68132],
            [-74.04500, 4.67500],
            [-74.05045, 4.67500],
            [-74.05045, 4.68132],
          ],
        ],
      },
      'properties': {
        'zoneId': _chico,
        'name': 'Chicó Norte',
        'level': 'BARRIO',
        'attribution': 'UAECD, CC BY 4.0',
      },
    },
  ],
  'sinGeometria': sinGeometria,
  'desconocidas': const <String>[],
  'atribuciones': const ['UAECD, CC BY 4.0'],
};

class _DatosFalsos implements MapaRemoteDataSource {
  _DatosFalsos({this.respuesta, this.zonas});

  Map<String, dynamic>? respuesta;
  List<Map<String, dynamic>>? zonas;
  List<String>? pedidas;

  @override
  Future<List<Map<String, dynamic>>> listarZonas() async =>
      zonas ??
      [
        {'id': _chapinero, 'name': 'Chapinero', 'level': 'LOCALIDAD', 'parentId': null, 'selectable': true},
        {'id': _chico, 'name': 'Chicó Norte', 'level': 'BARRIO', 'parentId': _chapinero, 'selectable': true},
      ];

  @override
  Future<GeometriasZonas> obtenerGeometrias(List<String> zonaIds) async {
    pedidas = zonaIds;
    return GatewayMapaDataSource.parsear(respuesta ?? _respuesta());
  }
}

void main() {
  group('conversión de GeoJSON', () {
    // El error clásico: GeoJSON es [lon, lat] y LatLng es (lat, lon).
    // Invertirlo no rompe ninguna prueba de forma, pero manda Bogotá al golfo
    // de Adén. Por eso se afirma el hemisferio, no solo el número de puntos.
    test('invierte el par para que el punto caiga en Bogotá, no en el golfo de Adén', () {
      final anillos = GeometriaZona.anillosDesdeGeoJson(
        _respuesta()['features'][0]['geometry'],
      );

      expect(anillos, hasLength(1));
      final p = anillos.first.first;
      expect(p.latitude, closeTo(4.68132, 0.00001));
      expect(p.longitude, closeTo(-74.05045, 0.00001));
      expect(p.latitude > 3 && p.latitude < 6, isTrue, reason: 'latitud de Bogotá');
      expect(p.longitude < -70, isTrue, reason: 'longitud de Bogotá');
    });

    test('acepta MultiPolygon y aporta un anillo por contorno', () {
      final anillos = GeometriaZona.anillosDesdeGeoJson({
        'type': 'MultiPolygon',
        'coordinates': [
          [[[-74.1, 4.6], [-74.0, 4.6], [-74.0, 4.7], [-74.1, 4.6]]],
          [[[-74.3, 4.8], [-74.2, 4.8], [-74.2, 4.9], [-74.3, 4.8]]],
        ],
      });
      expect(anillos, hasLength(2));
    });

    // C2: una geometría inválida es un caso previsto y la pantalla debe poder
    // mostrar el estado vacío, no caerse.
    test('devuelve vacío ante geometría nula, tipo desconocido o puntos insuficientes', () {
      expect(GeometriaZona.anillosDesdeGeoJson(null), isEmpty);
      expect(GeometriaZona.anillosDesdeGeoJson({'type': 'Point', 'coordinates': [-74, 4]}), isEmpty);
      expect(
        GeometriaZona.anillosDesdeGeoJson({'type': 'Polygon', 'coordinates': [[[-74, 4], [-74, 5]]]}),
        isEmpty,
        reason: 'dos puntos no son un polígono',
      );
      expect(
        GeometriaZona.anillosDesdeGeoJson({'type': 'Polygon', 'coordinates': [[['x', 'y'], [1, 2], [3, 4], [5, 6]]]}),
        hasLength(1),
        reason: 'descarta el punto inválido y conserva el resto',
      );
    });
  });

  group('MapaCubit', () {
    test('carga la localidad y pide su geometría junto con la de sus barrios', () async {
      final datos = _DatosFalsos();
      final cubit = MapaCubit(datos);

      await cubit.cargar();

      expect(cubit.state.estado, MapaEstado.listo);
      expect(cubit.state.localidadId, _chapinero);
      expect(datos.pedidas, [_chapinero, _chico]);
      expect(cubit.state.geometrias, hasLength(1));
      expect(cubit.state.atribuciones, ['UAECD, CC BY 4.0']);
    });

    test('C2 informa las zonas sin límite cargado en vez de dibujar algo aproximado', () async {
      final datos = _DatosFalsos(respuesta: _respuesta(sinGeometria: [_chapinero]));
      final cubit = MapaCubit(datos);

      await cubit.cargar();

      expect(cubit.state.sinGeometria, [_chapinero]);
      expect(cubit.state.geometrias.every((g) => g.zonaId != _chapinero), isTrue);
    });

    test('sin ninguna geometría dibujable el estado es vacío, no listo', () async {
      final datos = _DatosFalsos(
        respuesta: {
          'type': 'FeatureCollection',
          'features': const [],
          'sinGeometria': [_chapinero],
          'desconocidas': const <String>[],
          'atribuciones': const <String>[],
        },
      );
      final cubit = MapaCubit(datos);

      await cubit.cargar();

      expect(cubit.state.estado, MapaEstado.vacio);
      expect(cubit.state.geometrias, isEmpty);
    });

    test('sin localidades en el catálogo el estado es vacío y no se pide geometría', () async {
      final datos = _DatosFalsos(zonas: const []);
      final cubit = MapaCubit(datos);

      await cubit.cargar();

      expect(cubit.state.estado, MapaEstado.vacio);
      expect(datos.pedidas, isNull);
    });

    test('no pide más zonas de las que Core admite por petición', () {
      expect(GatewayMapaDataSource.maxZonasPorPeticion, 20);
    });
  });
}
