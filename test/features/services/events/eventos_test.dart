import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/platform/selector_fotos.dart';
import 'package:mani/features/services/events/data/eventos_datasource.dart';
import 'package:mani/features/services/events/presentation/eventos_cubit.dart';
import 'package:mani/features/services/events/presentation/eventos_seccion.dart';
import 'package:mani/features/services/quotes/domain/cotizacion.dart';
import 'package:mani/features/services/requests/domain/entities/foto_adjunta.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

// PNG mínimo válido (cabecera), suficiente para FotoAdjunta.
final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
]);

Map<String, dynamic> _eventoJson(String id, String tipo, {bool foto = false}) =>
    {
      'id': id,
      'tipo': tipo,
      'descripcion': 'Cambié la tubería',
      'registradoEn': '2026-10-27T16:00:00Z',
      'autor': {'id': 'u-1', 'rol': 'ALIADO'},
      'tieneEvidencia': foto,
    };

class _FuenteFake implements FuenteEventos {
  List<EventoServicio> lista = [];
  Object? falloRegistrar;
  final claves = <String>[];
  final registros = <String>[];

  @override
  Future<List<EventoServicio>> listar(String solicitudId) async => lista;

  @override
  Future<EventoServicio> registrar(
    String solicitudId, {
    required TipoEventoAliado tipo,
    required String observacion,
    required String claveIdempotencia,
    FotoAdjunta? foto,
  }) async {
    claves.add(claveIdempotencia);
    if (falloRegistrar != null) throw falloRegistrar!;
    registros.add('${tipo.valor}:$observacion:${foto != null}');
    final e = EventoServicio.fromJson(
      _eventoJson(
        'e${lista.length + 1}',
        'EJECUCION_${tipo.valor}',
        foto: foto != null,
      ),
    );
    lista = [...lista, e];
    return e;
  }
}

class _SelectorFijo implements SelectorFotos {
  @override
  Future<List<ArchivoLocal>> seleccionar() async => [
    ArchivoLocal(nombre: 'fuga.png', bytes: _png),
  ];
}

void main() {
  test(
    'el modelo traduce los tipos conocidos y deja los desconocidos tal cual',
    () {
      expect(
        EventoServicio.fromJson(
          _eventoJson('a', 'INICIO_EJECUCION'),
        ).etiquetaTipo,
        'Inicio del servicio',
      );
      expect(
        EventoServicio.fromJson(
          _eventoJson('a', 'EJECUCION_NOVEDAD'),
        ).etiquetaTipo,
        'Novedad',
      );
      expect(
        EventoServicio.fromJson(_eventoJson('a', 'OTRO_TIPO')).etiquetaTipo,
        'OTRO_TIPO',
      );
    },
  );

  group('SCRUM-869 · fuente por el Gateway', () {
    late List<http.BaseRequest> peticiones;
    late http.Response Function(http.BaseRequest) responder;

    GatewayFuenteEventos fuente() => GatewayFuenteEventos(
      GatewayClient(
        baseUrl: 'http://gateway.local',
        tokenProvider: () async => 'jwt',
        correlationId: () => 'corr',
        initialRetryDelay: Duration.zero,
        httpClient: MockClient.streaming((r, body) async {
          peticiones.add(r);
          await body.drain<void>();
          final res = responder(r);
          return http.StreamedResponse(
            Stream.value(res.bodyBytes),
            res.statusCode,
            headers: res.headers,
          );
        }),
      ),
    );

    setUp(() => peticiones = []);

    test(
      'registrar va en multipart con tipo, observación, foto y la clave también en la cabecera',
      () async {
        responder = (_) => http.Response(
          jsonEncode({
            'evento': _eventoJson('e1', 'EJECUCION_AVANCE', foto: true),
          }),
          201,
          headers: _json,
        );
        final e = await fuente().registrar(
          'sol-1',
          tipo: TipoEventoAliado.avance,
          observacion: 'Cambié la tubería',
          claveIdempotencia: 'clave-1',
          foto: FotoAdjunta.crear(nombre: 'fuga.png', bytes: _png),
        );
        final r = peticiones.single as http.MultipartRequest;
        expect(r.url.path, '/api/v1/core/solicitudes/sol-1/eventos');
        expect(r.fields, {
          'tipo': 'AVANCE',
          'observacion': 'Cambié la tubería',
          'claveIdempotencia': 'clave-1',
        });
        expect(r.files.single.field, 'foto');
        expect(r.headers[GatewayClient.headerIdempotencyKey], 'clave-1');
        expect(e.tieneEvidencia, isTrue);
      },
    );

    test(
      'un 503 se reintenta con la misma clave: el registro es idempotente',
      () async {
        var n = 0;
        responder = (_) => ++n == 1
            ? http.Response('{"error":"caído"}', 503)
            : http.Response(
                jsonEncode({'evento': _eventoJson('e1', 'EJECUCION_AVANCE')}),
                200,
                headers: _json,
              );
        await fuente().registrar(
          'sol-1',
          tipo: TipoEventoAliado.avance,
          observacion: 'Hola',
          claveIdempotencia: 'clave-1',
        );
        expect(peticiones, hasLength(2));
      },
    );

    test('un 409 de Core se traduce con su texto, sin el código', () async {
      responder = (_) => http.Response(
        jsonEncode({
          'error':
              'MANI-EVT-409E: solo se registran eventos durante la ejecución (estado FINALIZADA)',
        }),
        409,
        headers: _json,
      );
      await expectLater(
        fuente().registrar(
          'sol-1',
          tipo: TipoEventoAliado.avance,
          observacion: 'Hola',
          claveIdempotencia: 'c',
        ),
        throwsA(
          isA<CotizacionFailure>().having(
            (f) => f.mensajeUsuario,
            'mensaje',
            'Solo se registran eventos durante la ejecución (estado FINALIZADA)',
          ),
        ),
      );
    });

    test(
      'listar lee la secuencia; una respuesta sin la lista es un error',
      () async {
        responder = (_) => http.Response(
          jsonEncode({
            'eventos': [
              _eventoJson('e1', 'INICIO_EJECUCION'),
              _eventoJson('e2', 'EJECUCION_AVANCE'),
            ],
          }),
          200,
          headers: _json,
        );
        final lista = await fuente().listar('sol-1');
        expect(lista.map((e) => e.id), ['e1', 'e2']);
        expect(lista.first.autorRol, 'ALIADO');

        responder = (_) => http.Response('{}', 200, headers: _json);
        await expectLater(
          fuente().listar('sol-1'),
          throwsA(isA<CotizacionFailure>()),
        );
      },
    );
  });

  group('SCRUM-869 · cubit', () {
    test(
      'la clave se conserva si el envío falla y se renueva cuando queda registrado',
      () async {
        var n = 0;
        final f = _FuenteFake()
          ..falloRegistrar = const CotizacionFailure(
            CotizacionErrorTipo.sinConexion,
          );
        final cubit = EventosCubit(
          f,
          'sol-1',
          generarClave: () => 'clave-${++n}',
        );

        expect(
          await cubit.registrar(
            tipo: TipoEventoAliado.avance,
            observacion: 'Hola',
          ),
          isFalse,
        );
        expect(cubit.state.avisoEsError, isTrue);
        f.falloRegistrar = null;
        expect(
          await cubit.registrar(
            tipo: TipoEventoAliado.avance,
            observacion: 'Hola',
          ),
          isTrue,
        );

        expect(f.claves, ['clave-1', 'clave-1']);
        expect(cubit.state.clave, 'clave-2');
        expect(cubit.state.eventos, hasLength(1));
        expect(cubit.state.aviso, 'Evento registrado.');
      },
    );
  });

  group('SCRUM-869 · sección', () {
    Future<_FuenteFake> montar(
      WidgetTester tester, {
      required bool puedeRegistrar,
    }) async {
      final f = _FuenteFake();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BlocProvider(
                create: (_) => EventosCubit(f, 'sol-1')..cargar(),
                child: EventosSeccion(
                  puedeRegistrar: puedeRegistrar,
                  selectorFotos: _SelectorFijo(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return f;
    }

    testWidgets(
      'en ejecución el aliado registra una novedad con foto y la ve en la bitácora',
      (tester) async {
        final f = await montar(tester, puedeRegistrar: true);
        expect(find.text('Aún no hay eventos registrados.'), findsOneWidget);

        await tester.tap(find.text('Novedad'));
        await tester.enterText(
          find.byKey(const Key('campo-observacion-evento')),
          'Fuga adicional',
        );
        await tester.tap(find.byKey(const Key('btn-foto-evento')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('foto-evento-elegida')), findsOneWidget);

        await tester.tap(find.byKey(const Key('btn-registrar-evento')));
        await tester.pumpAndSettle();
        expect(f.registros, ['NOVEDAD:Fuga adicional:true']);
        expect(find.text('Novedad'), findsWidgets);
        expect(find.byKey(const Key('evento-e1')), findsOneWidget);
        // El formulario queda limpio para el siguiente evento.
        expect(find.byKey(const Key('foto-evento-elegida')), findsNothing);
      },
    );

    testWidgets('con menos de 3 caracteres no se puede registrar', (
      tester,
    ) async {
      await montar(tester, puedeRegistrar: true);
      await tester.enterText(
        find.byKey(const Key('campo-observacion-evento')),
        'no',
      );
      await tester.pump();
      final boton = find.byKey(const Key('btn-registrar-evento'));
      await tester.tap(boton);
      await tester.pump();
      expect(find.text('Aún no hay eventos registrados.'), findsOneWidget);
    });

    testWidgets(
      'fuera de la ejecución solo se ve la bitácora, sin formulario',
      (tester) async {
        await montar(tester, puedeRegistrar: false);
        expect(find.byKey(const Key('seccion-eventos')), findsOneWidget);
        expect(find.byKey(const Key('btn-registrar-evento')), findsNothing);
      },
    );
  });
}
