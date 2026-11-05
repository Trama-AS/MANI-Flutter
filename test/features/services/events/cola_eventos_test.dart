import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/platform/url_opener.dart';
import 'package:mani/features/services/events/data/almacen_cola_eventos.dart';
import 'package:mani/features/services/events/data/almacen_cola_eventos_io.dart';
import 'package:mani/features/services/events/data/cola_eventos.dart';
import 'package:mani/features/services/events/data/eventos_datasource.dart';
import 'package:mani/features/services/events/presentation/eventos_cubit.dart';
import 'package:mani/features/services/events/presentation/eventos_seccion.dart';
import 'package:mani/features/services/quotes/domain/cotizacion.dart';
import 'package:mani/features/services/requests/domain/entities/foto_adjunta.dart';

const _sinRed = CotizacionFailure(CotizacionErrorTipo.sinConexion);
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

/// Fuente que responde según [fallos]: un fallo por llamada, en orden; sin
/// fallos registra el evento.
class _Fuente implements FuenteEventos {
  final fallos = <CotizacionFailure?>[];
  final enviados = <Map<String, Object?>>[];
  List<EventoServicio> lista = [];
  int listados = 0;

  @override
  Future<List<EventoServicio>> listar(String solicitudId) async {
    listados++;
    return lista;
  }

  @override
  Future<EventoServicio> registrar(
    String solicitudId, {
    required TipoEventoAliado tipo,
    required String observacion,
    required String claveIdempotencia,
    FotoAdjunta? foto,
    DateTime? ocurridoEn,
  }) async {
    final fallo = fallos.isEmpty ? null : fallos.removeAt(0);
    if (fallo != null) throw fallo;
    enviados.add({
      'solicitud': solicitudId,
      'clave': claveIdempotencia,
      'observacion': observacion,
      'foto': foto != null,
      'ocurridoEn': ocurridoEn,
    });
    final e = EventoServicio(
      id: 'e${enviados.length}',
      tipo: 'EJECUCION_${tipo.valor}',
      descripcion: observacion,
      registradoEn: DateTime.utc(2026, 10, 28, 15, 30),
      ocurridoEn: ocurridoEn,
      autorRol: 'ALIADO',
    );
    lista = [...lista, e];
    return e;
  }

  @override
  Future<Uri> urlEvidencia(String solicitudId, String eventoId) =>
      throw UnimplementedError();
}

class _Opener implements UrlOpener {
  @override
  Future<bool> abrir(Uri url) async => true;
}

EventoPendiente _pendiente(
  String clave, {
  String usuario = 'u-1',
  String solicitud = 's-1',
  FotoAdjunta? foto,
  String observacion = 'Sin señal en el sótano',
}) => EventoPendiente(
  clave: clave,
  usuarioId: usuario,
  solicitudId: solicitud,
  tipo: TipoEventoAliado.avance,
  observacion: observacion,
  ocurridoEn: DateTime.utc(2026, 10, 28, 15, 10),
  foto: foto,
);

void main() {
  group('ColaEventos', () {
    late AlmacenColaEnMemoria almacen;
    late ColaEventos cola;
    String? usuario = 'u-1';

    setUp(() {
      usuario = 'u-1';
      almacen = AlmacenColaEnMemoria();
      cola = ColaEventos(almacen, usuarioActual: () => usuario);
    });

    test('C1: envía en orden con su clave y su hora de captura y vacía la '
        'cola', () async {
      final fuente = _Fuente();
      await cola.encolar(_pendiente('k1'));
      await cola.encolar(_pendiente('k2', solicitud: 's-2'));

      final r = await cola.sincronizar(fuente);

      expect(r, const ResultadoSincronizacion(enviados: 2));
      expect(fuente.enviados.map((e) => e['clave']), ['k1', 'k2']);
      expect(
        fuente.enviados.first['ocurridoEn'],
        DateTime.utc(2026, 10, 28, 15, 10),
      );
      expect(await cola.pendientes(), isEmpty);
    });

    test('C2: sin red, 5xx, sesión vencida o respuesta rara el evento se '
        'queda y la ronda se corta', () async {
      for (final tipo in [
        CotizacionErrorTipo.sinConexion,
        CotizacionErrorTipo.servicioNoDisponible,
        CotizacionErrorTipo.sinSesion,
        CotizacionErrorTipo.desconocido,
      ]) {
        await cola.vaciar();
        await cola.encolar(_pendiente('k1'));
        await cola.encolar(_pendiente('k2'));
        final fuente = _Fuente()..fallos.add(CotizacionFailure(tipo));

        final r = await cola.sincronizar(fuente);

        expect(r.enviados, 0, reason: '$tipo');
        expect(fuente.enviados, isEmpty, reason: 'no salta al siguiente');
        expect((await cola.pendientes()).map((e) => e.clave), ['k1', 'k2']);
      }
    });

    test('C2: un rechazo de Core saca el evento de la cola, se informa y '
        'sigue con los demás', () async {
      for (final tipo in [
        CotizacionErrorTipo.conflicto,
        CotizacionErrorTipo.datosInvalidos,
        CotizacionErrorTipo.sinPermiso,
        CotizacionErrorTipo.noEncontrada,
      ]) {
        await cola.vaciar();
        await cola.encolar(_pendiente('k1'));
        await cola.encolar(_pendiente('k2'));
        final fuente = _Fuente()
          ..fallos.add(
            CotizacionFailure(tipo, 'El evento se tomó después del fin'),
          );

        final r = await cola.sincronizar(fuente);

        expect(r.enviados, 1, reason: '$tipo');
        expect(r.rechazados.single.evento.clave, 'k1');
        expect(r.rechazados.single.motivo, isNotEmpty);
        expect(await cola.pendientes(), isEmpty);
      }
    });

    test('C3: la cola es del usuario de la sesión: sin sesión no hay nada y '
        'lo de otro usuario no se muestra ni se envía', () async {
      await cola.encolar(_pendiente('mio'));
      await cola.encolar(_pendiente('ajeno', usuario: 'u-2'));
      final fuente = _Fuente();

      expect((await cola.pendientes()).map((e) => e.clave), ['mio']);
      await cola.sincronizar(fuente);
      expect(fuente.enviados.map((e) => e['clave']), ['mio']);

      usuario = null;
      expect(await cola.pendientes(), isEmpty);
      await cola.vaciar();
      expect(await almacen.leer(), isEmpty);
    });

    test(
      'límite del PO: 20 eventos o 50 MB, lo primero que se alcance',
      () async {
        for (var i = 0; i < ColaEventos.maxEventos; i++) {
          await cola.encolar(_pendiente('k$i'));
        }
        await expectLater(
          cola.encolar(_pendiente('k20')),
          throwsA(isA<ColaLlena>()),
        );
        expect(
          const ColaLlena().mensajeUsuario,
          contains('20 eventos o 50 MB'),
        );

        await cola.vaciar();
        final foto = FotoAdjunta.crear(
          nombre: 'grande.png',
          bytes: Uint8List(FotoAdjunta.maxBytes),
        );
        for (var i = 0; i < 10; i++) {
          await cola.encolar(_pendiente('f$i', foto: foto, observacion: ''));
        }
        await expectLater(
          cola.encolar(_pendiente('f10', foto: foto)),
          throwsA(isA<ColaLlena>()),
        );
      },
    );

    test('dos rondas a la vez no envían dos veces', () async {
      await cola.encolar(_pendiente('k1'));
      final fuente = _Fuente();
      await Future.wait([cola.sincronizar(fuente), cola.sincronizar(fuente)]);
      expect(fuente.enviados, hasLength(1));
    });

    test(
      'en la web (y en las pruebas en escritorio) no hay modo sin conexión',
      () async {
        final web = ColaEventos(
          AlmacenColaEnMemoria(disponible: false),
          usuarioActual: () => 'u-1',
        );
        expect(web.disponible, isFalse);
        expect(await web.pendientes(), isEmpty);
        expect(crearAlmacenColaEventos().disponible, isFalse);
      },
    );
  });

  group('AlmacenColaEnArchivos', () {
    late Directory dir;
    late AlmacenColaEnArchivos almacen;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('cola873');
      almacen = AlmacenColaEnArchivos(
        disponible: true,
        directorio: () async => Directory('${dir.path}/cola_eventos'),
      );
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test(
      'persiste en orden, con la foto aparte, y sobrevive a otra instancia',
      () async {
        final foto = FotoAdjunta.crear(nombre: 'fuga.png', bytes: _png);
        await almacen.agregar(_pendiente('k1', foto: foto));
        await almacen.agregar(_pendiente('k2'));

        final otra = AlmacenColaEnArchivos(
          disponible: true,
          directorio: () async => Directory('${dir.path}/cola_eventos'),
        );
        final leidos = await otra.leer();
        expect(leidos, [_pendiente('k1', foto: foto), _pendiente('k2')]);
        expect(leidos.first.foto!.bytes, _png);
        expect(leidos.first.ocurridoEn.isUtc, isTrue);
        expect(File('${dir.path}/cola_eventos/k1.foto').existsSync(), isTrue);

        await otra.quitar('k1');
        expect((await almacen.leer()).map((e) => e.clave), ['k2']);
        expect(File('${dir.path}/cola_eventos/k1.foto').existsSync(), isFalse);
      },
    );

    test(
      'al vaciar (cierre de sesión) no queda nada en el dispositivo',
      () async {
        await almacen.agregar(
          _pendiente(
            'k1',
            foto: FotoAdjunta.crear(nombre: 'a.png', bytes: _png),
          ),
        );
        await almacen.vaciar();
        expect(Directory('${dir.path}/cola_eventos').existsSync(), isFalse);
        expect(await almacen.leer(), isEmpty);
        await almacen.vaciar();
      },
    );

    test('un índice dañado o una fila sin su foto no se envían', () async {
      await almacen.agregar(
        _pendiente(
          'k1',
          foto: FotoAdjunta.crear(nombre: 'a.png', bytes: _png),
        ),
      );
      await almacen.agregar(_pendiente('k2'));
      await File('${dir.path}/cola_eventos/k1.foto').delete();
      expect((await almacen.leer()).map((e) => e.clave), ['k2']);

      final indice = File('${dir.path}/cola_eventos/cola.json');
      await indice.writeAsString('[{"clave":"x","tipo":"FIESTA"},');
      expect(await almacen.leer(), isEmpty);
      await indice.writeAsString('[{"clave":"x","tipo":"FIESTA"}]');
      expect(await almacen.leer(), isEmpty);
    });
  });

  group('EventosCubit sin conexión', () {
    late _Fuente fuente;
    late ColaEventos cola;
    var claves = 0;

    EventosCubit cubit() => EventosCubit(
      fuente,
      's-1',
      cola: cola,
      usuarioActual: () => 'u-1',
      generarClave: () => 'clave-${++claves}',
      ahora: () => DateTime.utc(2026, 10, 28, 15, 10),
      intervaloReintento: const Duration(milliseconds: 20),
    );

    setUp(() {
      claves = 0;
      fuente = _Fuente();
      cola = ColaEventos(AlmacenColaEnMemoria(), usuarioActual: () => 'u-1');
    });

    test('C1: sin red el evento queda pendiente con la clave del intento y la '
        'hora de captura; al volver la red se envía solo', () async {
      final c = cubit();
      addTearDown(c.close);
      fuente.fallos.add(_sinRed);

      final ok = await c.registrar(
        tipo: TipoEventoAliado.novedad,
        observacion: 'Fuga en el sótano',
      );

      expect(ok, isTrue);
      expect(c.state.pendientes.single.clave, 'clave-1');
      expect(
        c.state.pendientes.single.ocurridoEn,
        DateTime.utc(2026, 10, 28, 15, 10),
      );
      expect(c.state.clave, 'clave-2');
      expect(c.state.aviso, contains('Sin conexión'));
      expect(c.state.avisoEsError, isFalse);

      // El temporizador de reintento la envía cuando hay red.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(fuente.enviados.single['clave'], 'clave-1');
      expect(
        fuente.enviados.single['ocurridoEn'],
        DateTime.utc(2026, 10, 28, 15, 10),
      );
      expect(c.state.pendientes, isEmpty);
      expect(
        c.state.eventos.single.ocurridoEn,
        DateTime.utc(2026, 10, 28, 15, 10),
      );
      expect(c.state.aviso, 'Se envió 1 evento que estaba pendiente.');
    });

    test(
      'al cargar se envía lo pendiente; un rechazo de Core se avisa',
      () async {
        await cola.encolar(_pendiente('k1'));
        await cola.encolar(_pendiente('k2'));
        fuente.fallos.add(
          const CotizacionFailure(
            CotizacionErrorTipo.conflicto,
            'El evento se tomó después del fin de la ejecución',
          ),
        );
        final c = cubit();
        addTearDown(c.close);

        await c.cargar();

        expect(fuente.enviados.map((e) => e['clave']), ['k2']);
        expect(c.state.pendientes, isEmpty);
        expect(c.state.avisoEsError, isTrue);
        expect(c.state.aviso, contains('Sin señal en el sótano'));
        expect(c.state.aviso, contains('después del fin'));
      },
    );

    test(
      'varios enviados se cuentan; si la lista no carga no es un fallo',
      () async {
        await cola.encolar(_pendiente('k1'));
        await cola.encolar(_pendiente('k2'));
        final c = cubit();
        addTearDown(c.close);
        await c.sincronizar();
        expect(c.state.aviso, 'Se enviaron 2 eventos que estaban pendientes.');
        expect(fuente.listados, 1);
      },
    );

    test('con la cola llena no se registra y se pide conectarse', () async {
      for (var i = 0; i < ColaEventos.maxEventos; i++) {
        await cola.encolar(_pendiente('k$i', solicitud: 's-9'));
      }
      final c = cubit();
      addTearDown(c.close);
      fuente.fallos.add(_sinRed);

      final ok = await c.registrar(
        tipo: TipoEventoAliado.avance,
        observacion: 'Otro avance',
      );

      expect(ok, isFalse);
      expect(c.state.avisoEsError, isTrue);
      expect(c.state.aviso, contains('20 eventos'));
      expect(c.state.clave, 'clave-1', reason: 'reintentar no duplica');
    });

    test(
      'sin cola (web o cliente) un fallo de red se informa como antes',
      () async {
        final c = EventosCubit(fuente, 's-1', generarClave: () => 'k');
        addTearDown(c.close);
        fuente.fallos.add(_sinRed);
        final ok = await c.registrar(
          tipo: TipoEventoAliado.avance,
          observacion: 'Avance',
        );
        expect(ok, isFalse);
        expect(c.state.avisoEsError, isTrue);
        expect(c.state.pendientes, isEmpty);
        await c.sincronizar();
        expect(fuente.enviados, isEmpty);
      },
    );

    test('un rechazo distinto de la red no se encola', () async {
      final c = cubit();
      addTearDown(c.close);
      fuente.fallos.add(
        const CotizacionFailure(CotizacionErrorTipo.conflicto, 'Finalizado'),
      );
      expect(
        await c.registrar(tipo: TipoEventoAliado.avance, observacion: 'Avance'),
        isFalse,
      );
      expect(await cola.pendientes(), isEmpty);
    });
  });

  testWidgets('la bitácora muestra los pendientes con su hora de captura y '
      'los envía a pedido; un evento que llegó tarde muestra las dos horas', (
    tester,
  ) async {
    final fuente = _Fuente()
      ..lista = [
        EventoServicio(
          id: 'e0',
          tipo: 'EJECUCION_AVANCE',
          descripcion: 'Tomado sin señal',
          registradoEn: DateTime(2026, 10, 28, 10, 30),
          ocurridoEn: DateTime(2026, 10, 28, 10, 5),
          autorRol: 'ALIADO',
        ),
      ];
    final cola = ColaEventos(
      AlmacenColaEnMemoria(),
      usuarioActual: () => 'u-1',
    );
    await cola.encolar(
      _pendiente(
        'k1',
        foto: FotoAdjunta.crear(nombre: 'a.png', bytes: _png),
      ),
    );
    fuente.fallos.add(_sinRed);
    final c = EventosCubit(
      fuente,
      's-1',
      cola: cola,
      usuarioActual: () => 'u-1',
      intervaloReintento: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BlocProvider.value(
              value: c,
              child: EventosSeccion(
                puedeRegistrar: false,
                urlOpener: _Opener(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(c.cargar);
    await tester.pump();

    expect(find.byKey(const Key('eventos-pendientes')), findsOneWidget);
    expect(find.text('1 evento pendiente de enviar'), findsOneWidget);
    expect(find.byKey(const Key('pendiente-k1')), findsOneWidget);
    expect(find.textContaining('Tomado:'), findsNWidgets(2));
    expect(find.textContaining('Enviado:'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('btn-enviar-pendientes')));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();

    expect(fuente.enviados.single['clave'], 'k1');
    expect(find.byKey(const Key('eventos-pendientes')), findsNothing);
    await c.close();
  });
}
