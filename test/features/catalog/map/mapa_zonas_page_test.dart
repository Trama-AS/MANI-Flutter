import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/catalog/map/data/mapa_remote_datasource.dart';
import 'package:mani/features/catalog/map/domain/entities/geometria_zona.dart';
import 'package:mani/features/catalog/map/presentation/bloc/mapa_cubit.dart';
import 'package:mani/features/catalog/map/presentation/pages/mapa_zonas_page.dart';

const _chapinero = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a13';
const _chico = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a15';

/// Recorte real de Chicó Norte, en orden longitud-latitud como lo entrega el
/// contrato.
final _anillo = GeometriaZona.anillosDesdeGeoJson({
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
});

class _CubitFalso extends Cubit<MapaState> implements MapaCubit {
  _CubitFalso(super.initialState);

  @override
  Future<void> cargar() async {}

  @override
  Future<void> seleccionar(String localidadId) async {
    seleccionada = localidadId;
  }

  String? seleccionada;

}

Widget _app(MapaState estado, {_CubitFalso? cubit}) {
  return MaterialApp(
    home: BlocProvider<MapaCubit>.value(
      value: cubit ?? _CubitFalso(estado),
      child: const MapaZonasPage(),
    ),
  );
}

void main() {
  testWidgets('dibuja el mapa con un polígono por cada anillo del límite', (tester) async {
    await tester.pumpWidget(
      _app(
        MapaState(
          estado: MapaEstado.listo,
          localidades: const [
            {'id': _chapinero, 'name': 'Chapinero', 'level': 'LOCALIDAD'},
          ],
          localidadId: _chapinero,
          geometrias: [
            GeometriaZona(
              zonaId: _chico,
              nombre: 'Chicó Norte',
              nivel: 'BARRIO',
              anillos: _anillo,
              atribucion: 'UAECD, CC BY 4.0',
            ),
          ],
          atribuciones: const ['UAECD, CC BY 4.0'],
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('mapa_zonas')), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);

    final capa = tester.widget<PolygonLayer>(find.byType(PolygonLayer));
    expect(capa.polygons, hasLength(1));
    // El punto llega al mapa como (latitud, longitud): si la conversión se
    // invirtiera, esto caería fuera de Bogotá.
    final p = capa.polygons.first.points.first;
    expect(p.latitude, closeTo(4.68132, 0.00001));
    expect(p.longitude, closeTo(-74.05045, 0.00001));
  });

  testWidgets('sin geometrías muestra el estado vacío y no dibuja un mapa', (tester) async {
    await tester.pumpWidget(_app(const MapaState(estado: MapaEstado.vacio)));
    await tester.pump();

    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text('Sin límites para mostrar'), findsOneWidget);
    // C2: se dice que no se dibuja una forma aproximada, no se insinúa que no haya zonas.
    expect(find.textContaining('No se dibuja una forma aproximada'), findsOneWidget);
  });

  testWidgets('avisa cuántas zonas quedaron sin límite cargado', (tester) async {
    await tester.pumpWidget(
      _app(
        MapaState(
          estado: MapaEstado.listo,
          geometrias: [
            GeometriaZona(
              zonaId: _chico,
              nombre: 'Chicó Norte',
              nivel: 'BARRIO',
              anillos: _anillo,
              atribucion: 'UAECD',
            ),
          ],
          sinGeometria: const [_chapinero],
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('mapa_sin_geometria')), findsOneWidget);
    expect(find.textContaining('1 zona(s) sin límite cargado'), findsOneWidget);
  });

  testWidgets('marca la sede ubicada y avisa de las que no tienen punto', (tester) async {
    await tester.pumpWidget(
      _app(
        MapaState(
          estado: MapaEstado.listo,
          geometrias: [
            GeometriaZona(
              zonaId: _chico,
              nombre: 'Chicó Norte',
              nivel: 'BARRIO',
              anillos: _anillo,
              atribucion: 'UAECD',
            ),
          ],
          sitios: const [
            SitioUbicado(
              id: 's1', nombre: 'Sede Norte', zonaId: _chico,
              latitud: 4.68, longitud: -74.048,
            ),
          ],
          sitiosSinUbicacion: 2,
        ),
      ),
    );
    await tester.pump();

    final capa = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    expect(capa.markers, hasLength(1));
    // El punto llega como (latitud, longitud): invertirlo lo saca de Bogotá.
    expect(capa.markers.first.point.latitude, closeTo(4.68, 0.0001));
    expect(capa.markers.first.point.longitude, closeTo(-74.048, 0.0001));

    // C2: las sedes sin punto se cuentan, no se ubican en el centroide.
    expect(find.byKey(const Key('mapa_sitios_sin_ubicacion')), findsOneWidget);
    expect(find.textContaining('2 sede(s) sin ubicación capturada'), findsOneWidget);
  });

  testWidgets('una sede ubicada basta para dibujar el mapa sin ningún límite', (tester) async {
    await tester.pumpWidget(
      _app(
        const MapaState(
          estado: MapaEstado.listo,
          sitios: [
            SitioUbicado(
              id: 's1', nombre: 'Sede Norte', zonaId: _chapinero,
              latitud: 4.65, longitud: -74.06,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(tester.widget<PolygonLayer>(find.byType(PolygonLayer)).polygons, isEmpty);
    expect(tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers, hasLength(1));
  });

  // El aliado ve resaltada su cobertura. Es lectura: cambiarla es de
  // «Zona de cobertura», por lista y hasta localidad.
  testWidgets('resalta en verde la zona declarada como cobertura y explica que no se edita aquí', (tester) async {
    final conCobertura = GeometriaZona(
      zonaId: _chico, nombre: 'Chicó Norte', nivel: 'BARRIO',
      anillos: _anillo, atribucion: 'UAECD',
    );
    await tester.pumpWidget(
      _app(
        MapaState(
          estado: MapaEstado.listo,
          geometrias: [conCobertura],
          coberturaPropia: const {_chico},
        ),
      ),
    );
    await tester.pump();

    final poligono = tester.widget<PolygonLayer>(find.byType(PolygonLayer)).polygons.first;
    expect(poligono.borderColor, const Color(0xFF166534), reason: 'verde de cobertura');
    expect(poligono.borderStrokeWidth, 3, reason: 'trazo más marcado que una zona cualquiera');

    expect(find.byKey(const Key('mapa_leyenda_cobertura')), findsOneWidget);
    expect(find.textContaining('usa Cobertura en el menú'), findsOneWidget);
  });

  testWidgets('sin cobertura propia no hay leyenda ni verde', (tester) async {
    await tester.pumpWidget(
      _app(
        MapaState(
          estado: MapaEstado.listo,
          geometrias: [
            GeometriaZona(
              zonaId: _chico, nombre: 'Chicó Norte', nivel: 'BARRIO',
              anillos: _anillo, atribucion: 'UAECD',
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    final poligono = tester.widget<PolygonLayer>(find.byType(PolygonLayer)).polygons.first;
    expect(poligono.borderColor, const Color(0xFFC2410C), reason: 'naranja de barrio');
    expect(find.byKey(const Key('mapa_leyenda_cobertura')), findsNothing);
  });

  testWidgets('el error ofrece reintentar', (tester) async {
    await tester.pumpWidget(
      _app(const MapaState(estado: MapaEstado.error, mensajeError: 'Gateway caído')),
    );
    await tester.pump();

    expect(find.text('No se pudo cargar el mapa'), findsOneWidget);
    expect(find.text('Gateway caído'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
  });

  testWidgets('con varias localidades el selector cambia la que se pinta', (tester) async {
    final cubit = _CubitFalso(
      const MapaState(
        estado: MapaEstado.vacio,
        localidades: [
          {'id': _chapinero, 'name': 'Chapinero', 'level': 'LOCALIDAD'},
          {'id': 'otra-id', 'name': 'Suba', 'level': 'LOCALIDAD'},
        ],
        localidadId: _chapinero,
      ),
    );
    await tester.pumpWidget(_app(cubit.state, cubit: cubit));
    await tester.pump();

    expect(find.byKey(const Key('mapa_selector_localidad')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mapa_selector_localidad')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suba').last);
    await tester.pumpAndSettle();

    expect(cubit.seleccionada, 'otra-id');
  });
}
