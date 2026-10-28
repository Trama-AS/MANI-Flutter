import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mani/core/di/injection_container.dart';
import 'package:mani/core/session/guardas_ruta.dart';
import 'package:mani/core/session/rol_usuario.dart';
import 'package:mani/features/auth/domain/entities/auth_failure.dart';
import 'package:mani/features/auth/domain/entities/user_entity.dart';
import 'package:mani/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:mani/features/auth/domain/usecases/login_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_aliado_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_cliente_empresa_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_cliente_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_empresa_usecase.dart';
import 'package:mani/features/auth/presentation/bloc/auth_cubit.dart';
import 'package:mani/features/auth/presentation/pages/login_page.dart';

class _RepoFalso implements IAuthRepository {
  final intentos = <({String email, String password})>[];
  AuthFailure? falla;

  @override
  Future<UserEntity> signInWithEmail({
    required String email,
    required String password,
  }) async {
    intentos.add((email: email, password: password));
    if (falla != null) throw falla!;
    return const UserEntity(id: 'u-1', email: 'ana@mani.app');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

AuthCubit _cubit(_RepoFalso repo) => AuthCubit(
  loginUseCase: LoginUseCase(repo),
  registerClienteUseCase: RegisterClienteUseCase(repo),
  registerAliadoUseCase: RegisterAliadoUseCase(repo),
  registerEmpresaUseCase: RegisterEmpresaUseCase(repo),
  registerClienteEmpresaUseCase: RegisterClienteEmpresaUseCase(repo),
);

/// SCRUM-1370 (HU-M02-02): inicio de sesión por tipo de usuario. La pestaña es presentación; el destino y los permisos
/// los decide el rol del token (C3).
void main() {
  late _RepoFalso repo;

  setUp(() {
    repo = _RepoFalso();
    sl.registerFactory<AuthCubit>(() => _cubit(repo));
  });
  tearDown(() async => GetIt.instance.reset());

  Future<void> montar(
    WidgetTester tester, {
    required RolUsuario rolDelToken,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1800);
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: rutaLogin,
      routes: [
        GoRoute(
          path: rutaLogin,
          builder: (_, _) => LoginPage(rolDeSesion: () => rolDelToken),
        ),
        GoRoute(
          path: rutaInicio,
          builder: (_, _) => const Scaffold(body: Text('pantalla-de-inicio')),
        ),
        GoRoute(
          path: '/admin/verificacion-aliados',
          builder: (_, _) => const Scaffold(body: Text('pantalla-admin')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  Future<void> ingresar(WidgetTester tester, {String? pestana}) async {
    if (pestana != null) {
      await tester.tap(find.text(pestana));
      await tester.pump();
    }
    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'ana@mani.app');
    await tester.enterText(campos.at(1), 'Password123');
    await tester.tap(find.text('INGRESAR A MANI'));
    await tester.pumpAndSettle();
  }

  testWidgets('C1: el login ofrece los tres tipos de usuario y la empresa', (
    tester,
  ) async {
    await montar(tester, rolDelToken: RolUsuario.cliente);
    expect(find.text('Soy Cliente'), findsOneWidget);
    expect(find.text('Soy Aliado'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('EMPRESA / TENANT'), findsOneWidget);
  });

  testWidgets(
    'C1: cada tipo de usuario inicia sesión por su pestaña y aterriza en el inicio',
    (tester) async {
      for (final (pestana, rol) in [
        ('Soy Cliente', RolUsuario.cliente),
        ('Soy Aliado', RolUsuario.aliado),
        ('Admin', RolUsuario.adminTenant),
      ]) {
        await montar(tester, rolDelToken: rol);
        await ingresar(tester, pestana: pestana);

        expect(
          find.text('pantalla-de-inicio'),
          findsOneWidget,
          reason: pestana,
        );
        expect(
          find.text('¡Bienvenido a MANI!'),
          findsOneWidget,
          reason: 'la pestaña coincide con el rol del token',
        );
        await GetIt.instance.reset();
        sl.registerFactory<AuthCubit>(() => _cubit(repo));
      }
    },
  );

  testWidgets(
    'C3: un cliente que entra por la pestaña Admin aterriza en el inicio de cliente y se le avisa',
    (tester) async {
      await montar(tester, rolDelToken: RolUsuario.cliente);
      await ingresar(tester, pestana: 'Admin');

      expect(find.text('pantalla-de-inicio'), findsOneWidget);
      expect(
        find.text('pantalla-admin'),
        findsNothing,
        reason: 'la pestaña no abre la pantalla de administrador',
      );
      expect(
        find.text('Tu cuenta es de cliente: te llevamos a tu inicio.'),
        findsOneWidget,
      );
      expect(find.text('¡Bienvenido a MANI!'), findsNothing);
    },
  );

  testWidgets(
    'C3: un aliado por la pestaña Cliente tampoco cambia de rol: se le avisa de su rol real',
    (tester) async {
      await montar(tester, rolDelToken: RolUsuario.aliado);
      await ingresar(tester, pestana: 'Soy Cliente');
      expect(
        find.text('Tu cuenta es de aliado: te llevamos a tu inicio.'),
        findsOneWidget,
      );
      expect(find.text('pantalla-de-inicio'), findsOneWidget);
    },
  );

  testWidgets(
    'C3: al servidor solo llegan el correo y la contraseña; ni la pestaña ni la empresa elegidas',
    (tester) async {
      await montar(tester, rolDelToken: RolUsuario.cliente);
      await tester.tap(find.text('Admin'));
      await tester.pump();
      await ingresar(tester);

      expect(repo.intentos, [(email: 'ana@mani.app', password: 'Password123')]);
    },
  );

  testWidgets(
    'C2: credenciales inválidas muestran el mensaje genérico, no navegan y no crean sesión',
    (tester) async {
      repo.falla = const AuthFailure('Correo o contraseña incorrectos.');
      await montar(tester, rolDelToken: RolUsuario.desconocido);

      await ingresar(tester);

      expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
      expect(find.text('pantalla-de-inicio'), findsNothing);
      expect(
        find.text('INGRESAR A MANI'),
        findsOneWidget,
        reason: 'sigue en el formulario',
      );
    },
  );

  testWidgets('C2: sin correo ni contraseña no se llama al servidor', (
    tester,
  ) async {
    await montar(tester, rolDelToken: RolUsuario.cliente);
    await tester.tap(find.text('INGRESAR A MANI'));
    await tester.pumpAndSettle();
    expect(repo.intentos, isEmpty);
  });

  group('C3: el rol del token manda sobre cualquier selección (router)', () {
    test(
      'un cliente no puede abrir rutas de administrador ni de aliado: vuelve a su inicio',
      () {
        for (final destino in [
          '/admin/verificacion-aliados',
          '/admin/categorias',
          '/aliado/solicitudes',
        ]) {
          expect(
            resolverRedireccion(
              ubicacion: destino,
              esPublica: false,
              haySesion: true,
              rol: RolUsuario.cliente,
            ),
            rutaInicioPara(RolUsuario.cliente),
            reason: destino,
          );
        }
      },
    );

    test('un aliado no abre rutas de cliente ni de administrador', () {
      for (final destino in [
        '/cliente/solicitudes',
        '/cliente/pagos/abc',
        '/admin/categorias',
      ]) {
        expect(
          resolverRedireccion(
            ubicacion: destino,
            esPublica: false,
            haySesion: true,
            rol: RolUsuario.aliado,
          ),
          rutaInicioPara(RolUsuario.aliado),
          reason: destino,
        );
      }
    });

    test('un rol desconocido no abre ninguna entrada de negocio', () {
      for (final destino in [
        '/cliente/solicitudes',
        '/aliado/solicitudes',
        '/admin/categorias',
      ]) {
        expect(
          resolverRedireccion(
            ubicacion: destino,
            esPublica: false,
            haySesion: true,
            rol: RolUsuario.desconocido,
          ),
          rutaInicioPara(RolUsuario.desconocido),
          reason: destino,
        );
      }
    });

    test(
      'con sesión abierta, el login lleva al inicio del rol; sin sesión, las rutas piden login',
      () {
        expect(
          resolverRedireccion(
            ubicacion: rutaLogin,
            esPublica: true,
            haySesion: true,
            rol: RolUsuario.aliado,
          ),
          rutaInicioPara(RolUsuario.aliado),
        );
        expect(
          resolverRedireccion(
            ubicacion: '/cliente/solicitudes',
            esPublica: false,
            haySesion: false,
            rol: RolUsuario.desconocido,
          ),
          rutaLogin,
        );
      },
    );
  });
}
