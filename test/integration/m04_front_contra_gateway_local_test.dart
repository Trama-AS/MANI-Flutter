// Pruebas del front de M-04 contra el despliegue local real (Gateway + Core),
// no contra dobles: GestionCategoriasPage y CategoriesView con su cubit, sus
// casos de uso, su repositorio y el GatewayClient de verdad, hablando HTTP con
// `http://localhost:80`.
//
// Por qué existen, además de las pruebas maestras con `ServidorCategoriasFake`:
// esos dobles replican las reglas que CREEMOS que tiene el backend. Estas
// prueban las que tiene. Así se ve desde la pantalla lo que SCRUM-1390 añadió
// (auditoría al crear) y lo que SCRUM-1392 añadió (solo un aliado aprobado
// declara), que un doble no puede demostrar.
//
// Se SALTAN solas si el Gateway local no responde, para no romper el CI, que no
// levanta el stack. No sustituyen la evidencia de QA: el token aquí es el
// dev-token HS256 de Core, y la historia se acredita con ES256 de GoTrue en
// MANI-QA.
//
// Para correrlas:
//   cd MANI-Node && docker build -t mani-core-node:local .
//   cd MANI-APIGateway && docker compose up -d core-service
//   cd MANI-Flutter && flutter test test/integration/m04_front_contra_gateway_local_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/profile_categories/data/datasources/categories_remote_datasource.dart';
import 'package:mani/features/profile_categories/data/repositories/categories_repository_impl.dart';
import 'package:mani/features/profile_categories/domain/usecases/get_available_categories_usecase.dart';
import 'package:mani/features/profile_categories/domain/usecases/get_selected_categories_usecase.dart';
import 'package:mani/features/profile_categories/domain/usecases/save_selected_categories_usecase.dart';
import 'package:mani/features/profile_categories/presentation/bloc/categories_cubit.dart';
import 'package:mani/features/profile_categories/presentation/pages/categories_page.dart';

const _gateway = 'http://localhost:80';
const _core = '$_gateway/api/v1/core';
const _tenant = 'trama-demo';
// Aliado sembrado en memoria por Core con la verificación ya aprobada.
const _aliadoAprobado = 'demo-ally-1';

/// Cliente HTTP único de la prueba. Lo comparten la pantalla y las llamadas de
/// preparación, y se cierra al final del cuerpo con `_cerrar`: su temporizador
/// de conexión ociosa (15 s) nace dentro del reloj falso de `flutter_test` y,
/// si queda vivo, la prueba falla con «A Timer is still pending» aunque las
/// comprobaciones hayan pasado. `addTearDown` no sirve: corre después de que
/// flutter_test verifique los temporizadores pendientes.
late http.Client _cliente;

/// Cierra el cliente y deja que el temporizador muera antes de que termine el
/// cuerpo de la prueba.
Future<void> _cerrar(WidgetTester t) async {
  await t.runAsync(() async {
    _cliente.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
}

Future<bool> _gatewayArriba() async {
  try {
    final res = await _cliente
        .get(Uri.parse('$_core/health'))
        .timeout(const Duration(seconds: 3));
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// Token de desarrollo emitido por Core (HS256). Solo existe con
/// NODE_ENV=development|test; en cualquier otro entorno la ruta no está.
Future<String> _devToken({
  required String userId,
  String role = 'aliado',
}) async {
  final res = await _cliente.post(
    Uri.parse('$_core/auth/dev-token'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'userId': userId, 'tenantId': _tenant, 'role': role}),
  );
  return (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String;
}

/// Registra un aliado nuevo, que queda con la verificación PENDIENTE, y
/// devuelve su id de usuario. Es el caso del C2 de SCRUM-1392.
Future<String> _registrarAliadoPendiente() async {
  final sufijo = DateTime.now().microsecondsSinceEpoch;
  final peticion =
      http.MultipartRequest('POST', Uri.parse('$_core/auth/register/ally'))
        ..headers['X-Tenant-Slug'] = _tenant
        ..fields.addAll({
          'fullName': 'Aliado Pendiente Front',
          'email': 'pendiente.front.$sufijo@mani.test',
          'password': 'Prueba-1392-local',
          'phone': '3001112233',
          'categoriaId': 'd0eebc99-9c0b-4ef8-bb6d-6bb9bd380a18',
          'documentType': 'CC',
          // Los últimos dígitos del reloj, no los primeros: los primeros casi no
          // cambian entre corridas y Core responde 409 por documento repetido.
          'documentNumber': '$sufijo'.substring('$sufijo'.length - 10),
          'acceptsTerms': 'true',
        })
        ..files.add(
          http.MultipartFile.fromString(
            'cedula_ciudadania',
            '%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n',
            filename: 'cedula-prueba.pdf',
            contentType: MediaType.parse('application/pdf'),
          ),
        );
  final res = await http.Response.fromStream(await _cliente.send(peticion));
  final cuerpo = jsonDecode(res.body) as Map<String, dynamic>;
  final perfil = cuerpo['profile'];
  if (perfil is! Map<String, dynamic>) {
    throw StateError(
      'el registro del aliado no devolvió perfil: ${res.statusCode} ${res.body}',
    );
  }
  return perfil['id'] as String;
}

Widget _pantallaDelAliado(String token) {
  final gateway = GatewayClient(
    baseUrl: _gateway,
    tokenProvider: () async => token,
    httpClient: _cliente,
  );
  final repo = CategoriesRepositoryImpl(
    remoteDataSource: GatewayCategoriesDataSource(gateway),
  );
  return MaterialApp(
    home: BlocProvider(
      create: (_) => CategoriesCubit(
        getAvailableCategoriesUseCase: GetAvailableCategoriesUseCase(repo),
        getSelectedCategoriesUseCase: GetSelectedCategoriesUseCase(repo),
        saveSelectedCategoriesUseCase: SaveSelectedCategoriesUseCase(repo),
      ),
      child: const CategoriesView(),
    ),
  );
}

// Categorías del catálogo de Core cuyos ids SÍ son UUID, que es lo que la base
// acepta. El fixture en memoria además siembra 'cat-1'..'cat-3', que no lo son:
// ver SCRUM-1630.
const _plomeria = 'd0eebc99-9c0b-4ef8-bb6d-6bb9bd380a18';
const _electricidad = 'd0eebc99-9c0b-4ef8-bb6d-6bb9bd380a19';

Finder _tile(String id) => find.byKey(ValueKey('categoria-$id'));
Finder _marca(String id) =>
    find.descendant(of: _tile(id), matching: find.byIcon(Icons.check));

/// Deja que la pantalla termine sus llamadas HTTP de verdad: `pumpAndSettle` no
/// sirve aquí porque el reloj de la prueba no avanza el tiempo real de la red.
Future<void> _asentar(WidgetTester t, {int vueltas = 12}) async {
  for (var i = 0; i < vueltas; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _abrir(WidgetTester t, String token) async {
  await t.runAsync(() async => t.pumpWidget(_pantallaDelAliado(token)));
  await _asentar(t);
}

/// Deja al aliado sin categorías declaradas para que cada prueba parta de lo
/// mismo. Se hace por el Gateway, igual que la pantalla.
Future<void> _declararPorApi(String token, List<String> ids) async {
  await _cliente.put(
    Uri.parse('$_core/profiles/me/categories'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode({'categoryIds': ids}),
  );
}

void main() {
  setUp(() {
    _cliente = http.Client();
  });

  setUpAll(() {
    // `flutter_test` instala un cliente HTTP que responde 400 a todo: sin esto
    // no hay red real desde una prueba de widget.
    HttpOverrides.global = null;
  });

  testWidgets(
    'el aliado aprobado declara una categoría desde la pantalla y la recupera al recargar (C1)',
    (t) async {
      if (await t.runAsync(_gatewayArriba) != true) {
        markTestSkipped('Gateway local no responde en $_gateway');
        return;
      }
      final token = (await t.runAsync(
        () => _devToken(userId: _aliadoAprobado),
      ))!;
      await t.runAsync(() => _declararPorApi(token, [_electricidad]));

      await _abrir(t, token);

      // El catálogo y la selección vienen de Core, no de un doble.
      expect(find.text('Plomería y Redes Hidráulicas'), findsOneWidget);
      expect(
        _marca(_electricidad),
        findsOneWidget,
        reason: 'lo ya declarado llega marcado',
      );
      expect(_marca(_plomeria), findsNothing);

      // Añade plomería y guarda.
      await t.tap(_tile(_plomeria));
      await t.pump();
      expect(find.text('2 categoría(s) seleccionada(s)'), findsOneWidget);
      await t.tap(find.text('GUARDAR'));
      await _asentar(t);

      // Recargar es volver a montar la pantalla: la selección se pide otra vez
      // a Core, así que esto prueba persistencia, no estado en memoria.
      await _abrir(t, token);
      expect(_marca(_plomeria), findsOneWidget);
      expect(_marca(_electricidad), findsOneWidget);
      expect(find.text('2 categoría(s) seleccionada(s)'), findsOneWidget);

      await _cerrar(t);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'quitar una categoría y guardar deja la selección sin ella al recargar (C1)',
    (t) async {
      if (await t.runAsync(_gatewayArriba) != true) {
        markTestSkipped('Gateway local no responde en $_gateway');
        return;
      }
      final token = (await t.runAsync(
        () => _devToken(userId: _aliadoAprobado),
      ))!;
      await t.runAsync(
        () => _declararPorApi(token, [_plomeria, _electricidad]),
      );

      await _abrir(t, token);
      await t.tap(_tile(_electricidad));
      await t.pump();
      await t.tap(find.text('GUARDAR'));
      await _asentar(t);

      await _abrir(t, token);
      expect(_marca(_plomeria), findsOneWidget);
      expect(
        _marca(_electricidad),
        findsNothing,
        reason: 'la declaración reemplaza, no acumula',
      );

      await _cerrar(t);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'un aliado con la verificación pendiente ve un mensaje cierto al intentar declarar (C2, SCRUM-1392)',
    (t) async {
      if (await t.runAsync(_gatewayArriba) != true) {
        markTestSkipped('Gateway local no responde en $_gateway');
        return;
      }
      final pendiente = (await t.runAsync(_registrarAliadoPendiente))!;
      final token = (await t.runAsync(() => _devToken(userId: pendiente)))!;

      await _abrir(t, token);

      // Consultar el catálogo no exige verificación aprobada, así que la
      // pantalla carga: el rechazo del C2 es al declarar. Que un aliado sin
      // aprobar vea el catálogo es deliberado (puede preparar su selección);
      // lo que no puede es guardarla.
      expect(find.text('Plomería y Redes Hidráulicas'), findsOneWidget);

      // Se espera de más antes de tocar: la pantalla hace dos llamadas al abrir
      // (catálogo y selección guardada) y, si la segunda llega después del
      // toque, su respuesta pisa la selección recién hecha.
      await _asentar(t, vueltas: 20);

      // El registro ya le declaró la categoría que eligió en el formulario, así
      // que llega con una marcada aunque su verificación esté pendiente: ese
      // camino escribe la primera categoría al crear el aliado y no pasa por
      // el caso de uso de declarar. Para probar el C2 hay que intentar
      // declarar una SEGUNDA, que sí pasa por ahí.
      expect(_marca(_plomeria), findsOneWidget);
      await t.tap(_tile(_electricidad));
      await t.pump();
      expect(find.text('2 categoría(s) seleccionada(s)'), findsOneWidget);
      await t.tap(find.text('GUARDAR'));
      await _asentar(t);

      // Core responde 403 MANI-CAT-403 con el motivo de la verificación. El
      // mensaje de la pantalla tiene que ser cierto para este caso: este
      // usuario SÍ es aliado, lo que le falta es la aprobación.
      final textos = t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join(' | ');
      expect(
        textos,
        contains('verificación aprobada'),
        reason:
            'el mensaje no debe afirmar que baste con ser aliado; textos: $textos',
      );

      await _cerrar(t);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'las categorías sembradas con id que no es UUID se ofrecen en la pantalla y fallan al guardar (SCRUM-1630)',
    (t) async {
      if (await t.runAsync(_gatewayArriba) != true) {
        markTestSkipped('Gateway local no responde en $_gateway');
        return;
      }
      final token = (await t.runAsync(
        () => _devToken(userId: _aliadoAprobado),
      ))!;
      await t.runAsync(() => _declararPorApi(token, [_plomeria]));

      await _abrir(t, token);

      // 'cat-1' viene del fixture en memoria de Core y PostgreSQL lo rechazaría.
      // La pantalla lo muestra como si fuera seleccionable.
      expect(
        _tile('cat-1'),
        findsOneWidget,
        reason: 'el fixture no-UUID llega al front',
      );

      await t.tap(_tile('cat-1'));
      await t.pump();
      await t.tap(find.text('GUARDAR'));
      await _asentar(t);

      // Core lo rechaza con MANI-CAT-422C y el aliado ve el error, no un
      // guardado silencioso.
      final textos = t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join(' | ');
      expect(
        textos,
        contains('ya no están disponibles'),
        reason:
            'debería avisar que la categoría no está disponible; textos: $textos',
      );

      await _cerrar(t);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
