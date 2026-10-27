import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mani/features/auth/domain/entities/auth_failure.dart';
import 'package:mani/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:mani/features/auth/domain/repositories/i_recuperacion_contrasena_repository.dart';
import 'package:mani/features/auth/domain/usecases/recuperar_contrasena_usecases.dart';
import 'package:mani/features/auth/presentation/bloc/recuperacion_contrasena_cubit.dart';
import 'package:mani/features/auth/presentation/pages/olvide_contrasena_page.dart';
import 'package:mani/features/auth/presentation/pages/restablecer_contrasena_page.dart';
import 'package:mani/features/auth/presentation/validators/cliente_empresa_validators.dart';
import 'package:mani/features/auth/presentation/validators/credenciales_validators.dart';

class _FakeRepo implements IRecuperacionContrasenaRepository {
  _FakeRepo({this.falla});

  final AuthFailure? falla;
  final solicitudes = <Map<String, String>>[];
  final restablecimientos = <Map<String, String>>[];

  @override
  Future<void> solicitarEnlace({
    required String email,
    required String tenantSlug,
  }) async {
    if (falla != null) throw falla!;
    solicitudes.add({'email': email, 'tenant': tenantSlug});
  }

  @override
  Future<void> restablecer({
    required String accessToken,
    required String newPassword,
    required String tenantSlug,
  }) async {
    if (falla != null) throw falla!;
    restablecimientos.add({
      'token': accessToken,
      'password': newPassword,
      'tenant': tenantSlug,
    });
  }
}

RecuperacionContrasenaCubit _cubit(_FakeRepo repo) =>
    RecuperacionContrasenaCubit(
      solicitarUseCase: SolicitarRecuperacionUseCase(repo),
      restablecerUseCase: RestablecerContrasenaUseCase(repo),
    );

void main() {
  setUp(() => dotenv.testLoad(fileInput: 'TENANT_SLUG=acme-servicios'));

  group('validadores', () {
    test('CredencialesValidators: correo, contraseña de 8 y confirmación', () {
      expect(CredencialesValidators.email('ana@correo.co'), isNull);
      expect(CredencialesValidators.email(' '), isNotNull);
      expect(CredencialesValidators.email('no-es-correo'), isNotNull);
      expect(CredencialesValidators.password('1234567'), isNotNull);
      expect(CredencialesValidators.password('12345678'), isNull);
      expect(CredencialesValidators.confirmacion('', 'abc'), isNotNull);
      expect(
        CredencialesValidators.confirmacion('abd', 'abc'),
        'Las contraseñas no coinciden',
      );
      expect(CredencialesValidators.confirmacion('abc', 'abc'), isNull);
    });

    test('el formulario de cliente empresa sigue usando las mismas reglas', () {
      expect(
        ClienteEmpresaValidators.email('no-es-correo'),
        CredencialesValidators.email('no-es-correo'),
      );
      expect(
        ClienteEmpresaValidators.password('corta'),
        CredencialesValidators.password('corta'),
      );
    });
  });

  group('cubit', () {
    test(
      'solicitarEnlace pasa por cargando y termina en enlaceSolicitado',
      () async {
        final repo = _FakeRepo();
        final cubit = _cubit(repo);
        final estados = <EstadoRecuperacion>[];
        cubit.stream.listen((s) => estados.add(s.estado));

        await cubit.solicitarEnlace(email: 'ana@correo.co', tenantSlug: 'acme');
        await Future<void>.delayed(Duration.zero);

        expect(estados, [
          EstadoRecuperacion.cargando,
          EstadoRecuperacion.enlaceSolicitado,
        ]);
        expect(repo.solicitudes.single, {
          'email': 'ana@correo.co',
          'tenant': 'acme',
        });
      },
    );

    test('restablecer termina en restablecida', () async {
      final repo = _FakeRepo();
      final cubit = _cubit(repo);
      await cubit.restablecer(
        accessToken: 't',
        newPassword: 'ClaveNueva123',
        tenantSlug: 'acme',
      );
      expect(cubit.state.estado, EstadoRecuperacion.restablecida);
    });

    test('un AuthFailure llega como error con su mensaje', () async {
      final cubit = _cubit(
        _FakeRepo(falla: const AuthFailure('El enlace no sirve')),
      );
      await cubit.restablecer(
        accessToken: 't',
        newPassword: 'ClaveNueva123',
        tenantSlug: 'acme',
      );
      expect(cubit.state.estado, EstadoRecuperacion.error);
      expect(cubit.state.mensaje, 'El enlace no sirve');
    });
  });

  group('pantalla: olvidé mi contraseña', () {
    Future<_FakeRepo> abrir(WidgetTester tester, {_FakeRepo? repo}) async {
      final fake = repo ?? _FakeRepo();
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider(
            create: (_) => _cubit(fake),
            child: const OlvideContrasenaView(),
          ),
        ),
      );
      return fake;
    }

    testWidgets('valida el correo antes de enviar', (tester) async {
      final repo = await abrir(tester);

      await tester.tap(find.byKey(const Key('enviarEnlace')));
      await tester.pump();
      expect(find.text('El correo es obligatorio'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('email')), 'no-es-correo');
      await tester.tap(find.byKey(const Key('enviarEnlace')));
      await tester.pump();
      expect(find.text('Ingresa un correo electrónico válido'), findsOneWidget);
      expect(repo.solicitudes, isEmpty);
    });

    testWidgets(
      'envía con el tenant de TENANT_SLUG y muestra el mensaje que no revela si la cuenta existe',
      (tester) async {
        final repo = await abrir(tester);

        await tester.enterText(find.byKey(const Key('email')), 'ana@correo.co');
        await tester.tap(find.byKey(const Key('enviarEnlace')));
        await tester.pump();
        await tester.pump();

        expect(repo.solicitudes.single, {
          'email': 'ana@correo.co',
          'tenant': 'acme-servicios',
        });
        expect(find.byKey(const Key('mensajeEnlaceEnviado')), findsOneWidget);
        expect(find.text(OlvideContrasenaView.mensajeEnviado), findsOneWidget);
      },
    );

    testWidgets(
      'un error del servicio se muestra y el formulario sigue disponible',
      (tester) async {
        await abrir(
          tester,
          repo: _FakeRepo(
            falla: const AuthFailure('Se enviaron demasiados correos'),
          ),
        );

        await tester.enterText(find.byKey(const Key('email')), 'ana@correo.co');
        await tester.tap(find.byKey(const Key('enviarEnlace')));
        await tester.pump();
        await tester.pump();

        expect(find.text('Se enviaron demasiados correos'), findsOneWidget);
        expect(find.byKey(const Key('mensajeEnlaceEnviado')), findsNothing);
        expect(find.byKey(const Key('enviarEnlace')), findsOneWidget);
      },
    );
  });

  group('pantalla: restablecer contraseña', () {
    Future<_FakeRepo> abrir(
      WidgetTester tester,
      EnlaceRecuperacion enlace, {
      _FakeRepo? repo,
    }) async {
      final fake = repo ?? _FakeRepo();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => BlocProvider(
              create: (_) => _cubit(fake),
              child: RestablecerContrasenaView(enlace: enlace),
            ),
          ),
          GoRoute(
            path: '/login',
            builder: (_, _) => const Scaffold(body: Text('PANTALLA LOGIN')),
          ),
          GoRoute(
            path: '/forgot-password',
            builder: (_, _) => const Scaffold(body: Text('PANTALLA OLVIDE')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return fake;
    }

    const enlaceBueno = EnlaceRecuperacion(accessToken: 'tok-123');

    testWidgets(
      'un enlace sin token o vencido ofrece pedir otro y no muestra el formulario',
      (tester) async {
        for (final enlace in const [
          EnlaceRecuperacion(),
          EnlaceRecuperacion(expirado: true, accessToken: 'x'),
        ]) {
          await abrir(tester, enlace);

          expect(
            find.text(RestablecerContrasenaView.mensajeEnlaceInvalido),
            findsOneWidget,
          );
          expect(find.byKey(const Key('password')), findsNothing);

          await tester.tap(find.byKey(const Key('solicitarOtroEnlace')));
          await tester.pumpAndSettle();
          expect(find.text('PANTALLA OLVIDE'), findsOneWidget);
        }
      },
    );

    testWidgets('valida la longitud y que la confirmación coincida', (
      tester,
    ) async {
      final repo = await abrir(tester, enlaceBueno);

      await tester.enterText(find.byKey(const Key('password')), 'corta');
      await tester.enterText(find.byKey(const Key('confirmacion')), 'otra');
      await tester.tap(find.byKey(const Key('guardarContrasena')));
      await tester.pump();
      expect(find.text('Mínimo 8 caracteres'), findsOneWidget);
      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('password')),
        'ClaveNueva123',
      );
      await tester.enterText(
        find.byKey(const Key('confirmacion')),
        'ClaveDistinta1',
      );
      await tester.tap(find.byKey(const Key('guardarContrasena')));
      await tester.pump();
      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
      expect(repo.restablecimientos, isEmpty);
    });

    testWidgets(
      'con datos válidos envía el token del enlace y el tenant, y lleva al login',
      (tester) async {
        final repo = await abrir(tester, enlaceBueno);

        await tester.enterText(
          find.byKey(const Key('password')),
          'ClaveNueva123',
        );
        await tester.enterText(
          find.byKey(const Key('confirmacion')),
          'ClaveNueva123',
        );
        await tester.tap(find.byKey(const Key('guardarContrasena')));
        await tester.pump();
        await tester.pump();

        expect(repo.restablecimientos.single, {
          'token': 'tok-123',
          'password': 'ClaveNueva123',
          'tenant': 'acme-servicios',
        });
        expect(find.text('Contraseña actualizada'), findsOneWidget);

        await tester.tap(find.byKey(const Key('irAlLogin')));
        await tester.pumpAndSettle();
        expect(find.text('PANTALLA LOGIN'), findsOneWidget);
      },
    );

    testWidgets(
      'si el servicio rechaza el enlace se muestra su mensaje y no hay diálogo de éxito',
      (tester) async {
        await abrir(
          tester,
          enlaceBueno,
          repo: _FakeRepo(
            falla: const AuthFailure(
              'El enlace de recuperación no es válido o ya venció. Solicita uno nuevo.',
            ),
          ),
        );

        await tester.enterText(
          find.byKey(const Key('password')),
          'ClaveNueva123',
        );
        await tester.enterText(
          find.byKey(const Key('confirmacion')),
          'ClaveNueva123',
        );
        await tester.tap(find.byKey(const Key('guardarContrasena')));
        await tester.pump();
        await tester.pump();

        expect(find.textContaining('no es válido o ya venció'), findsOneWidget);
        expect(find.text('Contraseña actualizada'), findsNothing);
      },
    );
  });
}
