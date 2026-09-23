// Test maestro de US-04.1.1 — Crear solicitud (cliente).
//
// Recorre la historia de punta a punta con TODAS las capas reales:
//   CrearSolicitudPage → CrearSolicitudCubit → casos de uso →
//   SolicitudesClienteRepositoryImpl → SolicitudesClienteRemoteDataSource
// Solo se sustituye Supabase por `ServidorSolicitudesFake`, que replica las
// RPC de `006_crear_solicitud.sql` y el bucket privado de fotos (tenant y
// cliente desde la sesión, carpeta propia en Storage, idempotencia por clave).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/features/services/requests/data/repositories/solicitudes_cliente_repository_impl.dart';
import 'package:mani/features/services/requests/domain/usecases/solicitud_usecases.dart';
import 'package:mani/features/services/requests/presentation/bloc/crear_solicitud_cubit.dart';
import 'package:mani/features/services/requests/presentation/pages/crear_solicitud_page.dart';

import '../features/services/requests/fakes.dart';

class _App {
  _App(this.servidor, this.logs, this.selector);
  final ServidorSolicitudesFake servidor;
  final List<Map<String, dynamic>> logs;
  final FakeSelectorFotos selector;
}

Future<_App> _montar(WidgetTester t, ServidorSolicitudesFake servidor) async {
  t.view.physicalSize = const Size(420, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);

  final logs = <Map<String, dynamic>>[];
  final repo = SolicitudesClienteRepositoryImpl(
    servidor,
    logger: StructuredLogger(
      canal: 'test',
      sink: (l) => logs.add(jsonDecode(l) as Map<String, dynamic>),
    ),
  );
  var n = 0;
  final cubit = CrearSolicitudCubit(
    cargarCatalogo: CargarCatalogoSolicitud(repo),
    buscarZonas: BuscarZonas(repo),
    publicar: PublicarSolicitud(repo),
    generarClave: () => '00000000-0000-4000-8000-00000000000${++n}',
  );
  addTearDown(cubit.close);
  final selector = FakeSelectorFotos();

  await t.pumpWidget(
    MaterialApp(
      home: BlocProvider.value(
        value: cubit,
        child: CrearSolicitudPage(
          selectorFotos: selector,
          esperaBusqueda: Duration.zero,
        ),
      ),
    ),
  );
  await cubit.cargar();
  await t.pumpAndSettle();
  return _App(servidor, logs, selector);
}

Future<void> _tocar(WidgetTester t, Key key) async {
  await t.ensureVisible(find.byKey(key));
  await t.pumpAndSettle();
  await t.tap(find.byKey(key));
  await t.pumpAndSettle();
}

Future<void> _escribir(WidgetTester t, Key key, String texto) async {
  await t.enterText(find.byKey(key), texto);
  await t.testTextInput.receiveAction(TextInputAction.done);
  await t.pumpAndSettle();
}

/// Categoría → problema (con fotos opcionales) → avanza a ubicación.
Future<void> _hastaUbicacion(
  WidgetTester t,
  _App app, {
  List fotos = const [],
}) async {
  await _tocar(t, const ValueKey('categoria-cat-plo'));
  await _escribir(t, const ValueKey('campo-descripcion'), descripcionValida);
  if (fotos.isNotEmpty) {
    app.selector.siguiente = fotos.cast();
    await _tocar(t, const ValueKey('btn-agregar-fotos'));
  }
  await _tocar(t, const ValueKey('btn-continuar'));
}

void main() {
  testWidgets(
    'US-04.1.1 flujo completo: el cliente publica su problema con fotos',
    (t) async {
      final servidor = ServidorSolicitudesFake()..sembrarBase();
      final app = await _montar(t, servidor);

      // CA-1: solo ve los servicios ACTIVOS de su empresa (tenant).
      expect(find.text('Plomería'), findsOneWidget);
      expect(find.text('Pintura'), findsNothing, reason: 'inactiva');
      expect(
        find.text('Electricidad MTY'),
        findsNothing,
        reason: 'otro tenant',
      );

      // CA-2: describe el problema y adjunta fotos; las inválidas se explican
      // sin perder las válidas.
      await _hastaUbicacion(
        t,
        app,
        fotos: [foto('fuga.jpg'), foto('contrato.pdf'), foto('tubo.png')],
      );
      expect(find.textContaining('JPG, PNG o WEBP'), findsWidgets);

      // CA-3: sin direcciones guardadas, registra una nueva eligiendo el
      // barrio del catálogo (las zonas inactivas no aparecen).
      expect(find.byKey(const ValueKey('campo-direccion')), findsOneWidget);
      await _escribir(
        t,
        const ValueKey('campo-direccion'),
        'Calle Colima 120, Apto 401',
      );
      await _escribir(t, const ValueKey('campo-buscar-zona'), 'roma');
      await t.pump(const Duration(milliseconds: 1));
      await t.pumpAndSettle();
      expect(find.text('Roma Vieja'), findsNothing);
      await _tocar(t, const ValueKey('zona-z-roma'));
      await _tocar(t, const ValueKey('btn-continuar'));

      // CA-4: revisa todo antes de publicar.
      expect(find.text('Revisa y publica'), findsOneWidget);
      expect(find.text('2 fotos'), findsOneWidget);
      expect(find.text('Calle Colima 120, Apto 401'), findsOneWidget);

      // CA-5: publica → queda PENDIENTE con su descripción y fotos, lista
      // para que los aliados la vean y coticen.
      await _tocar(t, const ValueKey('btn-publicar'));
      expect(find.byKey(const ValueKey('titulo-publicada')), findsOneWidget);
      final fila = servidor.solicitudes.single;
      expect(fila['estado'], 'PENDIENTE');
      expect(fila['descripcion'], descripcionValida);
      expect(fila['fotos'], [
        'uid-ana/00000000-0000-4000-8000-000000000001/1.jpg',
        'uid-ana/00000000-0000-4000-8000-000000000001/2.png',
      ]);
      expect(
        servidor.storage.keys.every((r) => r.startsWith('uid-ana/')),
        isTrue,
        reason: 'fotos en la carpeta privada del cliente',
      );
      expect(servidor.sitios.single['direccion'], 'Calle Colima 120, Apto 401');
      expect(servidor.eventos.single['tipo_evento'], 'SOLICITUD_CREADA');

      // Trazabilidad: log JSON sin datos personales (ni descripción ni
      // dirección).
      final log = app.logs.single;
      expect(log['event'], 'US-04.1.1.crear_solicitud');
      expect(log['tenant_id'], 'tenant-a');
      expect(log['fotos'], 2);
      final texto = jsonEncode(log);
      expect(texto, isNot(contains('lavaplatos')));
      expect(texto, isNot(contains('Colima')));

      // CA-6: la siguiente solicitud propone la dirección ya guardada.
      await _tocar(t, const ValueKey('btn-otra-solicitud'));
      await _hastaUbicacion(t, app);
      expect(find.text('Calle Colima 120, Apto 401'), findsOneWidget);
      await _tocar(t, const ValueKey('btn-continuar'));
      await _tocar(t, const ValueKey('btn-publicar'));
      expect(servidor.solicitudes, hasLength(2));
      expect(servidor.sitios, hasLength(1), reason: 'reutiliza la dirección');
    },
  );

  testWidgets(
    'CA-7: si se pierde la respuesta, reintentar NO duplica la solicitud',
    (t) async {
      final servidor = ServidorSolicitudesFake()
        ..sembrarBase()
        ..perderRespuestaUnaVez = true;
      final app = await _montar(t, servidor);
      await _hastaUbicacion(t, app, fotos: [foto('fuga.jpg')]);
      await _escribir(t, const ValueKey('campo-direccion'), 'Calle Durango 45');
      await _escribir(t, const ValueKey('campo-buscar-zona'), 'cond');
      await t.pump(const Duration(milliseconds: 1));
      await t.pumpAndSettle();
      await _tocar(t, const ValueKey('zona-z-condesa'));
      await _tocar(t, const ValueKey('btn-continuar'));

      // Primer intento: el servidor la crea pero la respuesta no llega.
      await _tocar(t, const ValueKey('btn-publicar'));
      expect(find.textContaining('Sin conexión'), findsOneWidget);
      expect(find.text('Revisa y publica'), findsOneWidget);

      // El cliente reintenta: recibe la MISMA solicitud, con sus fotos.
      await _tocar(t, const ValueKey('btn-publicar'));
      expect(find.byKey(const ValueKey('titulo-publicada')), findsOneWidget);
      expect(servidor.solicitudes, hasLength(1));
      expect(servidor.eventos, hasLength(1));
      expect(servidor.storage.keys, servidor.solicitudes.single['fotos']);
    },
  );

  testWidgets('CA-8: un usuario que no es cliente no puede publicar', (
    t,
  ) async {
    final servidor = ServidorSolicitudesFake()
      ..sembrarBase()
      ..esCliente = false;
    await _montar(t, servidor);

    expect(
      find.text('Solo los clientes pueden publicar solicitudes de servicio.'),
      findsOneWidget,
    );
    expect(servidor.solicitudes, isEmpty);
  });
}
