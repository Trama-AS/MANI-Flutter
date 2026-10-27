import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/session/guardas_ruta.dart';
import 'package:mani/core/session/rol_usuario.dart';
import 'package:mani/features/services/eligible_allies/data/elegibles_datasource.dart';
import 'package:mani/features/services/eligible_allies/domain/aliado_elegible.dart';
import 'package:mani/features/services/eligible_allies/presentation/aliados_elegibles_cubit.dart';
import 'package:mani/features/services/eligible_allies/presentation/aliados_elegibles_page.dart';
import 'package:mani/features/services/tracking/data/seguimiento_datasource.dart';
import 'package:mani/features/services/tracking/domain/solicitud_seguimiento.dart';
import 'package:mani/features/services/tracking/presentation/mis_solicitudes_cubit.dart';
import 'package:mani/features/services/tracking/presentation/mis_solicitudes_page.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

Map<String, dynamic> _aliado(
  String id, {
  String tipo = 'PERSONA_NATURAL',
  int? posicion,
  double? puntaje,
  List<String>? razones,
}) => {
  'allyId': id,
  'nombreRazonSocial': 'Aliado $id',
  'tipo': tipo,
  'estadoVerificacion': 'VERIFICADO',
  'posicion': ?posicion,
  'puntaje': ?puntaje,
  'razones': ?razones,
};

Map<String, dynamic> _respuesta(
  List<Map<String, dynamic>> aliados, {
  Map<String, dynamic>? ranking,
  int? total,
}) => {
  'correlationId': 'c-1',
  'tenantId': 't-a',
  'zonaId': 'z-1',
  'categoriaId': 'cat-1',
  'page': 1,
  'pageSize': 50,
  'totalCount': total ?? aliados.length,
  'ranking': ?ranking,
  'matchedAllies': aliados,
};

/// Rules ordenó la lista, pero los puntajes vienen al revés del puesto: la
/// app debe respetar el orden del backend y no reordenar por puntaje.
final _ordenada = _respuesta(
  [
    _aliado('a3', posicion: 1, puntaje: 0.2, razones: ['Atiende tu zona']),
    _aliado('a1', posicion: 2, puntaje: 0.5),
    _aliado('a2', tipo: 'PERSONA_JURIDICA', posicion: 3, puntaje: 0.9),
  ],
  ranking: {'estado': 'APLICADO', 'criterio': 'CERCANIA_V1'},
);

class _FuenteFija implements FuenteElegibles {
  _FuenteFija(this.respuestas);

  /// Cada llamada consume la siguiente respuesta: una lista o una excepción.
  final List<Object> respuestas;
  final tipos = <TipoAliado?>[];

  @override
  Future<ListaElegibles> listar(String solicitudId, {TipoAliado? tipo}) async {
    final r = respuestas[tipos.length % respuestas.length];
    tipos.add(tipo);
    if (r is Exception) throw r;
    return r as ListaElegibles;
  }
}

void main() {
  group('SCRUM-1401 · modelo', () {
    test(
      'conserva el orden del backend aunque los puntajes estén invertidos',
      () {
        final l = ListaElegibles.fromJson(_ordenada);

        expect(l.ordenAplicado, isTrue);
        expect(l.criterio, 'CERCANIA_V1');
        expect(l.aliados.map((a) => a.id), ['a3', 'a1', 'a2']);
        expect(l.aliados.first.razones, ['Atiende tu zona']);
        expect(l.aliados.last.tipo, TipoAliado.personaJuridica);
        expect(l.aliados.last.etiquetaTipo, 'Empresa');
      },
    );

    test('dos lecturas de la misma respuesta son iguales', () {
      expect(
        ListaElegibles.fromJson(_ordenada),
        ListaElegibles.fromJson(_ordenada),
      );
      expect(
        ListaElegibles.fromJson(_ordenada),
        isNot(ListaElegibles.fromJson(_respuesta([]))),
      );
    });

    test('sin "ranking" se trata como NO_DISPONIBLE', () {
      final l = ListaElegibles.fromJson(_respuesta([_aliado('a1')]));

      expect(l.ordenAplicado, isFalse);
      expect(l.aliados.single.posicion, isNull);
    });

    test('NO_DISPONIBLE conserva el motivo', () {
      final l = ListaElegibles.fromJson(
        _respuesta(
          [_aliado('a1')],
          ranking: {'estado': 'NO_DISPONIBLE', 'motivo': 'RULES_NO_DISPONIBLE'},
        ),
      );

      expect(l.ordenAplicado, isFalse);
      expect(l.motivoSinOrden, 'RULES_NO_DISPONIBLE');
    });

    test('un tipo desconocido se muestra como lo envía Dispatch', () {
      final a = AliadoElegible.fromJson(_aliado('a1', tipo: 'COOPERATIVA'));

      expect(a.tipo, isNull);
      expect(a.etiquetaTipo, 'COOPERATIVA');
      expect(TipoAliado.desde(null), isNull);
    });

    test('un 200 sin "matchedAllies" no es una lista vacía', () {
      expect(
        () => ListaElegibles.fromJson({'totalCount': 0}),
        throwsA(
          isA<ElegiblesFailure>().having(
            (f) => f.tipo,
            'tipo',
            ElegiblesErrorTipo.desconocido,
          ),
        ),
      );
    });
  });

  group('SCRUM-1401 · datasource por el Gateway', () {
    late List<http.Request> peticiones;

    GatewayFuenteElegibles fuente(
      FutureOr<http.Response> Function(http.Request) h,
    ) {
      peticiones = [];
      return GatewayFuenteElegibles(
        GatewayClient(
          baseUrl: 'http://gateway.test',
          tokenProvider: () async => 'token',
          maxRetries: 0,
          httpClient: MockClient((req) async {
            peticiones.add(req);
            return h(req);
          }),
        ),
      );
    }

    Matcher falla(ElegiblesErrorTipo tipo) =>
        throwsA(isA<ElegiblesFailure>().having((f) => f.tipo, 'tipo', tipo));

    http.Response error(int status, [String? code]) => http.Response(
      jsonEncode({'error': 'x', 'status': status, 'code': ?code}),
      status,
      headers: _json,
    );

    test('consulta la solicitud con el filtro de tipo y el JWT', () async {
      final f = fuente(
        (_) => http.Response(jsonEncode(_ordenada), 200, headers: _json),
      );

      final l = await f.listar('sol-1', tipo: TipoAliado.empleadoDirecto);

      final uri = peticiones.single.url;
      expect(uri.path, '/api/v1/dispatch/requests/sol-1/eligible-allies');
      expect(uri.queryParameters, {
        'page': '1',
        'pageSize': '50',
        'tipo': 'EMPLEADO_DIRECTO',
      });
      expect(peticiones.single.headers['Authorization'], 'Bearer token');
      expect(l.aliados.map((a) => a.id), ['a3', 'a1', 'a2']);
    });

    test('sin filtro no envía "tipo"', () async {
      final f = fuente(
        (_) => http.Response(jsonEncode(_respuesta([])), 200, headers: _json),
      );

      await f.listar('sol-1');

      expect(
        peticiones.single.url.queryParameters.containsKey('tipo'),
        isFalse,
      );
    });

    test('traduce 400, 401, 403, 404, 503, otros y sin red', () async {
      final casos = {
        400: ElegiblesErrorTipo.tipoInvalido,
        401: ElegiblesErrorTipo.sinSesion,
        403: ElegiblesErrorTipo.noPermitido,
        404: ElegiblesErrorTipo.noEncontrada,
        503: ElegiblesErrorTipo.servicioNoDisponible,
        418: ElegiblesErrorTipo.desconocido,
      };
      for (final MapEntry(key: status, value: tipo) in casos.entries) {
        final f = fuente((_) => error(status));
        await expectLater(f.listar('sol-1'), falla(tipo), reason: '$status');
      }
      final f503 = fuente((_) => error(503, 'CORE_SERVICE_UNAVAILABLE'));
      await expectLater(
        f503.listar('sol-1'),
        falla(ElegiblesErrorTipo.servicioNoDisponible),
      );
      final sinRed = fuente((_) => throw http.ClientException('sin red'));
      await expectLater(
        sinRed.listar('sol-1'),
        falla(ElegiblesErrorTipo.sinConexion),
      );
    });

    test('cada error tiene un mensaje para el usuario', () {
      for (final t in ElegiblesErrorTipo.values) {
        final f = ElegiblesFailure(t, 'detalle');
        expect(f.mensajeUsuario, isNotEmpty);
        expect(f.toString(), contains(t.name));
      }
    });
  });

  group('SCRUM-1400/1401 · cubit', () {
    final lista = ListaElegibles.fromJson(_ordenada);
    final vacia = ListaElegibles.fromJson(_respuesta([]));

    test('carga y filtra por tipo', () async {
      final f = _FuenteFija([lista, vacia]);
      final cubit = AliadosElegiblesCubit(f, 'sol-1');

      await cubit.cargar();
      expect(cubit.state.lista, lista);
      await cubit.filtrar(TipoAliado.personaJuridica);

      expect(f.tipos, [null, TipoAliado.personaJuridica]);
      expect(cubit.state.tipo, TipoAliado.personaJuridica);
      expect(cubit.state.lista, vacia);
      await cubit.filtrar(TipoAliado.personaJuridica);
      expect(f.tipos, hasLength(2), reason: 'el mismo filtro no reconsulta');
      await cubit.close();
    });

    test('un error conserva la lista del mismo filtro', () async {
      final f = _FuenteFija([
        lista,
        const ElegiblesFailure(ElegiblesErrorTipo.servicioNoDisponible),
      ]);
      final cubit = AliadosElegiblesCubit(f, 'sol-1');

      await cubit.cargar();
      await cubit.cargar();

      expect(cubit.state.lista, lista);
      expect(cubit.state.error, contains('no está disponible'));
      await cubit.close();
    });

    test('un error inesperado se informa como desconocido', () async {
      final cubit = AliadosElegiblesCubit(
        _FuenteFija([StateError('x') as Object]),
        'sol-1',
      );

      await cubit.cargar();

      expect(cubit.state.error, contains('No pudimos consultar'));
      await cubit.close();
    });

    test('la respuesta tardía de un filtro anterior se descarta', () async {
      final lenta = Completer<ListaElegibles>();
      final fuente = _FuenteLenta(lenta.future, vacia);
      final cubit = AliadosElegiblesCubit(fuente, 'sol-1');

      final primera = cubit.cargar();
      await cubit.filtrar(TipoAliado.empleadoDirecto);
      lenta.complete(lista);
      await primera;

      expect(cubit.state.tipo, TipoAliado.empleadoDirecto);
      expect(cubit.state.lista, vacia);
      await cubit.close();
    });
  });

  group('SCRUM-1401 · pantalla', () {
    Future<_FuenteFija> montar(WidgetTester tester, List<Object> r) async {
      final f = _FuenteFija(r);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider(
              create: (_) => AliadosElegiblesCubit(f, 'sol-1')..cargar(),
              child: const AliadosElegiblesPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return f;
    }

    double y(WidgetTester tester, String id) =>
        tester.getTopLeft(find.byKey(Key('elegible-$id'))).dy;

    testWidgets('muestra el orden del backend con puesto y razones', (
      tester,
    ) async {
      await montar(tester, [ListaElegibles.fromJson(_ordenada)]);

      expect(find.byKey(const Key('elegibles-orden')), findsOneWidget);
      expect(y(tester, 'a3'), lessThan(y(tester, 'a1')));
      expect(y(tester, 'a1'), lessThan(y(tester, 'a2')));
      expect(find.text('• Atiende tu zona'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('sin ranking dice «Orden no disponible» y no numera', (
      tester,
    ) async {
      await montar(tester, [
        ListaElegibles.fromJson(
          _respuesta([
            _aliado('a1', razones: ['no se muestra']),
            _aliado('a2'),
          ], total: 80),
        ),
      ]);

      expect(find.byKey(const Key('elegibles-sin-orden')), findsOneWidget);
      expect(find.textContaining('Orden no disponible'), findsOneWidget);
      expect(find.text('1'), findsNothing);
      expect(find.text('• no se muestra'), findsNothing);
      expect(find.text('Mostrando 2 de 80 aliados.'), findsOneWidget);
    });

    testWidgets('los chips filtran por tipo y el vacío lo dice', (
      tester,
    ) async {
      final f = await montar(tester, [
        ListaElegibles.fromJson(_ordenada),
        ListaElegibles.fromJson(_respuesta([])),
      ]);

      await tester.tap(
        find.byKey(const Key('elegibles-tipo-EMPLEADO_DIRECTO')),
      );
      await tester.pumpAndSettle();

      expect(f.tipos, [null, TipoAliado.empleadoDirecto]);
      expect(
        find.textContaining('No hay aliados de este tipo'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('elegibles-tipo-TODOS')));
      await tester.pumpAndSettle();
      expect(f.tipos.last, isNull);
    });

    testWidgets('sin aliados y sin filtro lo dice', (tester) async {
      await montar(tester, [ListaElegibles.fromJson(_respuesta([]))]);

      expect(
        find.textContaining('Todavía no hay aliados disponibles'),
        findsOneWidget,
      );
    });

    testWidgets('un error se muestra y «Reintentar» vuelve a consultar', (
      tester,
    ) async {
      final f = await montar(tester, [
        const ElegiblesFailure(ElegiblesErrorTipo.noEncontrada),
        ListaElegibles.fromJson(_ordenada),
      ]);

      expect(find.byKey(const Key('elegibles-error')), findsOneWidget);
      expect(
        find.textContaining('No encontramos esa solicitud'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('elegibles-reintentar')));
      await tester.pumpAndSettle();

      expect(f.tipos, hasLength(2));
      expect(find.byKey(const Key('elegibles-error')), findsNothing);
      expect(find.byKey(const Key('elegible-a3')), findsOneWidget);
    });

    testWidgets('mientras carga muestra el indicador', (tester) async {
      final lenta = Completer<ListaElegibles>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider(
              create: (_) =>
                  AliadosElegiblesCubit(_FuenteLenta(lenta.future, null), 's')
                    ..cargar(),
              child: const AliadosElegiblesPage(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('elegibles-cargando')), findsOneWidget);
      lenta.complete(ListaElegibles.fromJson(_respuesta([])));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('elegibles-cargando')), findsNothing);
    });
  });

  group('SCRUM-1401 · acceso', () {
    test('solo el cliente puede abrir la ruta de elegibles', () {
      const ruta = '/cliente/solicitudes/sol-1/aliados';
      expect(rolPuedeAbrir(RolUsuario.cliente, ruta), isTrue);
      expect(rolPuedeAbrir(RolUsuario.aliado, ruta), isFalse);
      expect(rolPuedeAbrir(RolUsuario.adminTenant, ruta), isFalse);
    });

    testWidgets('«Ver aliados» solo aparece en las solicitudes pendientes', (
      tester,
    ) async {
      final abiertas = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider(
              create: (_) => MisSolicitudesCubit(_Seguimiento())..cargar(),
              child: MisSolicitudesPage(onVerAliados: abiertas.add),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ver-aliados-p1')), findsOneWidget);
      expect(find.byKey(const Key('ver-aliados-x1')), findsNothing);
      await tester.tap(find.byKey(const Key('ver-aliados-p1')));
      expect(abiertas, ['p1']);
    });
  });
}

/// La primera consulta espera a [primera]; las siguientes responden [luego].
class _FuenteLenta implements FuenteElegibles {
  _FuenteLenta(this.primera, this.luego);

  final Future<ListaElegibles> primera;
  final ListaElegibles? luego;
  var _llamadas = 0;

  @override
  Future<ListaElegibles> listar(String solicitudId, {TipoAliado? tipo}) =>
      _llamadas++ == 0 ? primera : Future.value(luego);
}

class _Seguimiento implements FuenteSeguimiento {
  SolicitudSeguimiento _s(String id, String estado) =>
      SolicitudSeguimiento.fromJson({
        'id': id,
        'estado': estado,
        'categoria': 'Plomería',
        'actualizadaEn': '2026-10-26T21:05:00Z',
      });

  @override
  Future<List<SolicitudSeguimiento>> listar() async => [
    _s('p1', 'PENDIENTE'),
    _s('x1', 'ASIGNADA'),
  ];

  @override
  Future<SolicitudSeguimiento> cancelar(String solicitudId, {String? motivo}) =>
      throw UnimplementedError();
}
