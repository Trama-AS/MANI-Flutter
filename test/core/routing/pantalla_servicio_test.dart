import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mani/core/di/injection_container.dart';
import 'package:mani/core/platform/selector_fotos.dart';
import 'package:mani/core/platform/url_opener.dart';
import 'package:mani/core/routing/app_router.dart';
import 'package:mani/features/messaging/data/mensajes_datasource.dart';
import 'package:mani/features/messaging/domain/mensaje.dart';
import 'package:mani/features/messaging/presentation/chat_page.dart';
import 'package:mani/features/services/events/data/eventos_datasource.dart';
import 'package:mani/features/services/execution/data/ejecucion_datasource.dart';
import 'package:mani/features/services/quotes/data/cotizaciones_datasource.dart';
import 'package:mani/features/services/quotes/domain/cotizacion.dart';
import 'package:mani/features/services/requests/domain/entities/foto_adjunta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _PkceEnMemoria extends GotrueAsyncStorage {
  final _datos = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _datos[key];
  @override
  Future<void> removeItem({required String key}) async => _datos.remove(key);
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _datos[key] = value;
}

class _Cotizaciones implements FuenteCotizaciones {
  @override
  Future<List<Cotizacion>> listar(String solicitudId) async => [
    Cotizacion.fromJson({
      'id': 'cot-1',
      'solicitudId': solicitudId,
      'version': 1,
      'estado': 'ACEPTADA',
      'valorManoObra': 100,
      'valorMateriales': 0,
      'total': 100,
    }),
  ];

  @override
  Future<Cotizacion> emitir(
    String solicitudId, {
    required String valorManoObra,
    required String valorMateriales,
  }) => throw UnimplementedError();

  @override
  Future<Cotizacion> responder(
    String cotizacionId,
    DecisionCotizacion decision, {
    String? texto,
  }) => throw UnimplementedError();
}

class _Ejecucion implements FuenteEjecucion {
  int consultas = 0;

  @override
  Future<Ejecucion> consultar(String solicitudId) async {
    consultas++;
    return Ejecucion.fromJson({
      'estado': 'EN_EJECUCION',
      'inicio': {'registradoEn': '2026-10-27T15:00:00Z'},
      'fin': null,
    });
  }

  @override
  Future<void> marcar(
    String solicitudId,
    HitoEjecucion hito, {
    String? observacion,
  }) async {}
}

class _Eventos implements FuenteEventos {
  int consultas = 0;

  @override
  Future<List<EventoServicio>> listar(String solicitudId) async {
    consultas++;
    return [
      EventoServicio.fromJson({
        'id': 'e1',
        'tipo': 'INICIO_EJECUCION',
        'registradoEn': '2026-10-27T15:00:00Z',
        'autor': {'id': 'u', 'rol': 'ALIADO'},
        'tieneEvidencia': false,
      }),
    ];
  }

  @override
  Future<EventoServicio> registrar(
    String solicitudId, {
    required TipoEventoAliado tipo,
    required String observacion,
    required String claveIdempotencia,
    FotoAdjunta? foto,
  }) => throw UnimplementedError();

  @override
  Future<Uri> urlEvidencia(String solicitudId, String eventoId) async =>
      Uri.parse('https://firmada/$eventoId');
}

class _Mensajes implements FuenteMensajes {
  @override
  Future<List<Mensaje>> listar(String solicitudId, {String? despuesDe}) async =>
      const [];

  @override
  Future<void> enviar(
    String solicitudId,
    String contenido, {
    required String claveIdempotencia,
  }) async {}
}

class _Opener implements UrlOpener {
  @override
  Future<bool> abrir(Uri url) async => true;
}

class _SinFotos implements SelectorFotos {
  @override
  Future<List<ArchivoLocal>> seleccionar() async => const [];
}

void main() {
  late _Ejecucion ejecucion;
  late _Eventos eventos;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'clave-de-prueba',
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _PkceEnMemoria(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );
    ejecucion = _Ejecucion();
    eventos = _Eventos();
    sl.registerSingleton<FuenteCotizaciones>(_Cotizaciones());
    sl.registerSingleton<FuenteEjecucion>(ejecucion);
    sl.registerSingleton<FuenteEventos>(eventos);
    sl.registerSingleton<FuenteMensajes>(_Mensajes());
    sl.registerSingleton<UrlOpener>(_Opener());
    sl.registerSingleton<SelectorFotos>(_SinFotos());
  });

  tearDownAll(sl.reset);

  GoRoute ruta(String nombre) => appRouter.configuration.routes
      .whereType<ShellRoute>()
      .single
      .routes
      .whereType<GoRoute>()
      .singleWhere((r) => r.name == nombre);

  Future<void> montar(WidgetTester tester, String nombre) async {
    final r = ruta(nombre);
    final ubicacion = r.path.replaceAll(':id', 'sol-1');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => r.builder!(
              context,
              GoRouterState(
                appRouter.configuration,
                uri: Uri.parse(ubicacion),
                matchedLocation: ubicacion,
                fullPath: r.path,
                pathParameters: const {'id': 'sol-1'},
                pageKey: ValueKey(ubicacion),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('el aliado ve cotización, ejecución y bitácora con formulario '
      'mientras el servicio está en ejecución', (tester) async {
    await montar(tester, 'cotizacion-aliado');

    expect(find.byKey(const Key('cotizacion-v1')), findsOneWidget);
    expect(find.byKey(const Key('seccion-ejecucion')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('seccion-eventos')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('btn-registrar-evento')), findsOneWidget);
  });

  testWidgets('el cliente ve la bitácora sin formulario y al deslizar se '
      'recargan la ejecución y los eventos', (tester) async {
    await montar(tester, 'cotizacion-cliente');
    await tester.scrollUntilVisible(
      find.byKey(const Key('seccion-eventos')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('evento-e1')), findsOneWidget);
    expect(find.byKey(const Key('btn-registrar-evento')), findsNothing);

    // RefreshIndicator solo se arma si el gesto empieza arriba. Con la cotización aceptada la lista lleva
    // el botón de pago (SCRUM-1432) y queda un poco desplazada, así que primero se vuelve al inicio.
    await tester.drag(find.byType(ListView).first, const Offset(0, 300));
    await tester.pumpAndSettle();

    final antesEjecucion = ejecucion.consultas;
    final antesEventos = eventos.consultas;
    await tester.fling(
      find.byType(ListView).first,
      const Offset(0, 2000),
      2000,
    );
    await tester.pumpAndSettle();
    expect(ejecucion.consultas, greaterThan(antesEjecucion));
    expect(eventos.consultas, greaterThan(antesEventos));
  });

  GoRouterState estado(GoRoute r, String ubicacion) => GoRouterState(
    appRouter.configuration,
    uri: Uri.parse(ubicacion),
    matchedLocation: ubicacion,
    fullPath: r.path,
    pathParameters: const {'id': 'sol-1'},
    pageKey: ValueKey(ubicacion),
  );

  // SCRUM-881: cada participante entra al chat del servicio desde la pantalla del servicio.
  for (final (nombre, destino, etiqueta) in [
    (
      'cotizacion-cliente',
      '/cliente/solicitudes/sol-1/chat',
      'Mensajes con el aliado',
    ),
    (
      'cotizacion-aliado',
      '/aliado/solicitudes/sol-1/chat',
      'Mensajes con el cliente',
    ),
  ]) {
    testWidgets('$nombre: el botón de mensajes abre $destino', (tester) async {
      final r = ruta(nombre);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) =>
                Scaffold(body: r.builder!(context, estado(r, '/ignorada'))),
          ),
          GoRoute(
            path: destino,
            builder: (_, _) => const Text('pantalla de chat'),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text(etiqueta), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn-abrir-chat')));
      await tester.pumpAndSettle();

      expect(find.text('pantalla de chat'), findsOneWidget);
    });
  }

  for (final nombre in ['chat-cliente', 'chat-aliado']) {
    testWidgets('$nombre arma la pantalla del chat con su Cubit', (
      tester,
    ) async {
      final r = ruta(nombre);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => r.builder!(context, estado(r, r.path)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChatPage), findsOneWidget);
      expect(find.byKey(const Key('chat-vacio')), findsOneWidget);
    });
  }
}
