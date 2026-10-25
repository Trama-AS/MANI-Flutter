import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/session/rol_usuario.dart';
import 'package:mani/core/shell/app_shell.dart';
import 'package:mani/core/shell/datos_sesion.dart';
import 'package:mani/core/shell/menu_por_rol.dart';

/// Arma un JWT sin firma válida: el shell solo lee el payload para pintar.
String _token(Map<String, dynamic> payload) {
  String parte(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${parte({'alg': 'ES256', 'typ': 'JWT'})}.${parte(payload)}.firma';
}

class _FuenteFija implements FuenteDatosSesion {
  _FuenteFija(this._datos);
  final DatosSesion _datos;
  @override
  Future<DatosSesion> cargar() async => _datos;
}

class _FuenteQueFalla implements FuenteDatosSesion {
  @override
  Future<DatosSesion> cargar() => Future.error(Exception('Core no responde'));
}

Future<void> _montar(
  WidgetTester tester, {
  required double ancho,
  required RolUsuario rol,
  FuenteDatosSesion? fuente,
  String ubicacion = '/',
  ValueChanged<String>? onNavegar,
  Future<void> Function()? onCerrarSesion,
}) async {
  tester.view.physicalSize = Size(ancho, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: AppShell(
        rol: rol,
        ubicacion: ubicacion,
        fuenteDatos:
            fuente ??
            _FuenteFija(
              const DatosSesion(
                nombreUsuario: 'Ana Pérez',
                nombreTenant: 'Plomería Express',
              ),
            ),
        onNavegar: onNavegar ?? (_) {},
        onCerrarSesion: onCerrarSesion ?? () async {},
        child: const Text('contenido de la pantalla'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('US-11.2.1 (SCRUM-1444) — rol de la sesión', () {
    test('traduce el claim del hook y los nombres de dominio de Core', () {
      expect(rolDesdeClaim('cliente'), RolUsuario.cliente);
      expect(rolDesdeClaim('CLIENT'), RolUsuario.cliente);
      expect(rolDesdeClaim('aliado'), RolUsuario.aliado);
      expect(rolDesdeClaim('ALLY'), RolUsuario.aliado);
      expect(rolDesdeClaim('admin_tenant'), RolUsuario.adminTenant);
      expect(rolDesdeClaim('ADMIN'), RolUsuario.adminTenant);
    });

    test('un rol vacío o desconocido no abre entradas de negocio', () {
      expect(rolDesdeClaim(null), RolUsuario.desconocido);
      expect(rolDesdeClaim('superusuario'), RolUsuario.desconocido);
      expect(entradasMenuPara(RolUsuario.desconocido).map((e) => e.ruta), [
        '/perfil/editar',
      ]);
    });

    test('lee app_metadata.user_role del access token', () {
      final token = _token({
        'sub': 'u-1',
        'app_metadata': {'tenant_id': 't-1', 'user_role': 'aliado'},
      });
      expect(rolDesdeAccessToken(token), RolUsuario.aliado);
    });

    test('acepta el claim alterno rol', () {
      final token = _token({
        'app_metadata': {'rol': 'admin_tenant'},
      });
      expect(rolDesdeAccessToken(token), RolUsuario.adminTenant);
    });

    test('token ausente, mal formado o sin app_metadata da desconocido', () {
      expect(rolDesdeAccessToken(null), RolUsuario.desconocido);
      expect(rolDesdeAccessToken('no-es-un-jwt'), RolUsuario.desconocido);
      expect(rolDesdeAccessToken('a.%%%.c'), RolUsuario.desconocido);
      expect(
        rolDesdeAccessToken(_token({'sub': 'u-1'})),
        RolUsuario.desconocido,
      );
    });
  });

  group('US-11.2.1 (SCRUM-1444) — entradas por rol', () {
    Set<String> rutas(RolUsuario rol) =>
        entradasMenuPara(rol).map((e) => e.ruta).toSet();

    test('cliente ve sus pantallas y ninguna de aliado ni de admin', () {
      final r = rutas(RolUsuario.cliente);
      expect(r, containsAll(['/cliente/solicitudes/nueva', '/cliente/sedes']));
      expect(r.any((x) => x.startsWith('/aliado')), isFalse);
      expect(r.any((x) => x.startsWith('/admin')), isFalse);
    });

    test('aliado ve bandeja, cobertura, categorías y disponibilidad', () {
      final r = rutas(RolUsuario.aliado);
      expect(
        r,
        containsAll([
          '/aliado/solicitudes',
          '/aliado/cobertura',
          '/categories',
          '/aliado/disponibilidad',
        ]),
      );
      expect(r.any((x) => x.startsWith('/admin')), isFalse);
      expect(r.any((x) => x.startsWith('/cliente')), isFalse);
    });

    test('admin del tenant ve verificación y catálogo de categorías', () {
      final r = rutas(RolUsuario.adminTenant);
      expect(
        r,
        containsAll(['/admin/verificacion-aliados', '/admin/categorias']),
      );
      expect(r.any((x) => x.startsWith('/aliado')), isFalse);
    });

    test('todos los roles conocidos tienen acceso a su perfil', () {
      for (final rol in RolUsuario.values) {
        expect(rutas(rol), contains('/perfil/editar'), reason: '$rol');
      }
    });
  });

  group('US-11.2.1 (SCRUM-1444) — datos de la cabecera por el Gateway', () {
    const jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

    GatewayClient gateway(Future<http.Response> Function(http.Request) h) =>
        GatewayClient(
          baseUrl: 'http://gateway.test',
          tokenProvider: () async => 'token',
          httpClient: MockClient(h),
          maxRetries: 0,
        );

    test('toma el nombre del perfil y el tenant del listado', () async {
      final rutas = <String>[];
      final fuente = GatewayFuenteDatosSesion(
        gateway((req) async {
          rutas.add(req.url.path);
          if (req.url.path == '/api/v1/core/profiles/me') {
            return http.Response(
              jsonEncode({
                'profile': {'fullName': 'Ana Pérez', 'tenantId': 't-2'},
              }),
              200,
              headers: jsonHeaders,
            );
          }
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 't-1', 'name': 'Otro tenant'},
                {'id': 't-2', 'name': 'Plomería Express'},
              ],
            }),
            200,
            headers: jsonHeaders,
          );
        }),
      );

      final datos = await fuente.cargar();

      expect(datos.nombreUsuario, 'Ana Pérez');
      expect(datos.nombreTenant, 'Plomería Express');
      expect(rutas, ['/api/v1/core/profiles/me', '/api/v1/core/tenants']);
    });

    test(
      'si el listado de tenants falla, la cabecera sale sin tenant',
      () async {
        final fuente = GatewayFuenteDatosSesion(
          gateway((req) async {
            if (req.url.path == '/api/v1/core/profiles/me') {
              return http.Response(
                jsonEncode({
                  'profile': {'fullName': 'Ana', 'tenantId': 't-2'},
                }),
                200,
                headers: jsonHeaders,
              );
            }
            return http.Response('{"error":"x"}', 500, headers: jsonHeaders);
          }),
        );

        final datos = await fuente.cargar();

        expect(datos.nombreUsuario, 'Ana');
        expect(datos.nombreTenant, isNull);
      },
    );

    test('un tenant que no está en el listado no se inventa', () async {
      final fuente = GatewayFuenteDatosSesion(
        gateway((req) async {
          if (req.url.path == '/api/v1/core/profiles/me') {
            return http.Response(
              jsonEncode({
                'profile': {'fullName': '', 'tenantId': 't-9'},
              }),
              200,
              headers: jsonHeaders,
            );
          }
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 't-1', 'name': 'Otro tenant'},
              ],
            }),
            200,
            headers: jsonHeaders,
          );
        }),
      );

      final datos = await fuente.cargar();

      expect(datos.nombreUsuario, 'Usuario');
      expect(datos.nombreTenant, isNull);
    });
  });

  group('US-11.2.1 (SCRUM-1444) — menú superior', () {
    testWidgets('en escritorio muestra usuario, rol, tenant y entradas', (
      tester,
    ) async {
      await _montar(tester, ancho: 1024, rol: RolUsuario.aliado);

      expect(find.byKey(const Key('menu-superior')), findsOneWidget);
      expect(find.text('Ana Pérez'), findsOneWidget);
      expect(find.text('Aliado · Plomería Express'), findsOneWidget);
      expect(find.text('Solicitudes'), findsOneWidget);
      expect(find.text('Cobertura'), findsOneWidget);
      expect(find.text('Verificación de aliados'), findsNothing);
      expect(find.byKey(const Key('menu-compacto')), findsNothing);
      expect(find.text('contenido de la pantalla'), findsOneWidget);
    });

    testWidgets('tocar una entrada navega a su ruta', (tester) async {
      String? destino;
      await _montar(
        tester,
        ancho: 1024,
        rol: RolUsuario.adminTenant,
        onNavegar: (r) => destino = r,
      );

      await tester.tap(find.byKey(const Key('menu-entrada-/admin/categorias')));

      expect(destino, '/admin/categorias');
    });

    testWidgets('cerrar sesión está disponible y llama al cierre', (
      tester,
    ) async {
      var cerro = false;
      await _montar(
        tester,
        ancho: 1024,
        rol: RolUsuario.cliente,
        onCerrarSesion: () async => cerro = true,
      );

      await tester.tap(find.byKey(const Key('menu-cerrar-sesion')));
      await tester.pumpAndSettle();

      expect(cerro, isTrue);
    });

    testWidgets('en móvil las entradas van en un menú desplegable', (
      tester,
    ) async {
      String? destino;
      await _montar(
        tester,
        ancho: 390,
        rol: RolUsuario.cliente,
        onNavegar: (r) => destino = r,
      );

      expect(find.byKey(const Key('menu-compacto')), findsOneWidget);
      expect(find.text('Mis sedes'), findsNothing);
      expect(find.byKey(const Key('menu-cerrar-sesion')), findsOneWidget);

      await tester.tap(find.byKey(const Key('menu-compacto')));
      await tester.pumpAndSettle();
      expect(find.text('Mis sedes'), findsOneWidget);

      await tester.tap(find.text('Mis sedes'));
      await tester.pumpAndSettle();
      expect(destino, '/cliente/sedes');
    });

    testWidgets('si Core no responde, el menú sigue usable con el rol', (
      tester,
    ) async {
      await _montar(
        tester,
        ancho: 1024,
        rol: RolUsuario.aliado,
        fuente: _FuenteQueFalla(),
      );

      expect(find.text('MANI'), findsOneWidget);
      expect(find.text('Aliado'), findsOneWidget);
      expect(find.text('Solicitudes'), findsOneWidget);
      expect(find.byKey(const Key('menu-cerrar-sesion')), findsOneWidget);
    });

    testWidgets('resalta la entrada de la ruta actual y sus subrutas', (
      tester,
    ) async {
      await _montar(
        tester,
        ancho: 1024,
        rol: RolUsuario.cliente,
        ubicacion: '/cliente/sedes',
      );

      final activa = tester.widget<TextButton>(
        find.byKey(const Key('menu-entrada-/cliente/sedes')),
      );
      final inactiva = tester.widget<TextButton>(
        find.byKey(const Key('menu-entrada-/perfil/editar')),
      );
      expect(activa.style?.backgroundColor?.resolve({}), isNotNull);
      expect(inactiva.style?.backgroundColor?.resolve({}), isNull);
    });
  });
}
