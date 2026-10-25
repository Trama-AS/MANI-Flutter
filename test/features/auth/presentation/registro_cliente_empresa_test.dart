import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/auth/domain/entities/user_entity.dart';
import 'package:mani/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:mani/features/auth/domain/usecases/login_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_aliado_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_cliente_empresa_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_cliente_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_empresa_usecase.dart';
import 'package:mani/features/auth/presentation/bloc/auth_cubit.dart';
import 'package:mani/features/auth/presentation/pages/registro_cliente_empresa_page.dart';
import 'package:mani/features/auth/presentation/validators/cliente_empresa_validators.dart';

class _FakeAuthRepository implements IAuthRepository {
  final List<Map<String, dynamic>> registrosEmpresa = [];

  @override
  Future<Map<String, dynamic>> registrarClienteEmpresa({
    required String email,
    required String password,
    required String razonSocial,
    required String nit,
    required String nombreRepresentante,
    required String tenantId,
    String? telefono,
  }) async {
    registrosEmpresa.add({
      'email': email,
      'razonSocial': razonSocial,
      'nit': nit,
      'nombreRepresentante': nombreRepresentante,
      'tenantId': tenantId,
    });
    return {'success': true, 'usuario_id': 'u-1'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  Future<UserEntity> signInWithEmail({
    required String email,
    required String password,
  }) => throw UnimplementedError();
}

AuthCubit _cubit(_FakeAuthRepository repo) => AuthCubit(
  loginUseCase: LoginUseCase(repo),
  registerClienteUseCase: RegisterClienteUseCase(repo),
  registerAliadoUseCase: RegisterAliadoUseCase(repo),
  registerEmpresaUseCase: RegisterEmpresaUseCase(repo),
  registerClienteEmpresaUseCase: RegisterClienteEmpresaUseCase(repo),
);

void main() {
  group('HU-M02-07 validadores', () {
    test('NIT: acepta 9 o 10 dígitos con DV opcional y con puntos', () {
      for (final nit in [
        '900123456',
        '9001234567',
        '900123456-7',
        '900.123.456-7',
        ' 900 123 456 ',
      ]) {
        expect(ClienteEmpresaValidators.nit(nit), isNull, reason: nit);
      }
    });

    test('NIT: rechaza vacío, corto, con letras o DV de dos cifras', () {
      for (final nit in [null, '', '12345', '90012345A', '900123456-78']) {
        expect(ClienteEmpresaValidators.nit(nit), isNotNull, reason: '$nit');
      }
    });

    test('normalizarNit quita puntos y espacios', () {
      expect(
        ClienteEmpresaValidators.normalizarNit(' 900.123.456-7 '),
        '900123456-7',
      );
    });

    test('email, contraseña (mínimo 8, como Core) y obligatorios', () {
      expect(ClienteEmpresaValidators.email('compras@andina.co'), isNull);
      expect(ClienteEmpresaValidators.email('no-es-email'), isNotNull);
      expect(ClienteEmpresaValidators.password('1234567'), isNotNull);
      expect(ClienteEmpresaValidators.password('12345678'), isNull);
      expect(
        ClienteEmpresaValidators.obligatorio(
          '  ',
          'La razón social es obligatoria',
        ),
        'La razón social es obligatoria',
      );
      expect(
        ClienteEmpresaValidators.obligatorio(
          'X',
          'La razón social es obligatoria',
        ),
        isNull,
      );
    });
  });

  group('HU-M02-07 cubit', () {
    test('sin aceptar términos no llama al registro', () async {
      final repo = _FakeAuthRepository();
      final cubit = _cubit(repo);

      await cubit.registerClienteEmpresa(
        email: 'a@b.co',
        password: 'Password123',
        razonSocial: 'Andina',
        nit: '900123456',
        nombreRepresentante: 'Laura',
        tenantId: 't',
        aceptaTerminos: false,
      );

      expect(cubit.state, isA<AuthError>());
      expect(repo.registrosEmpresa, isEmpty);
    });

    test('con términos aceptados registra y emite éxito', () async {
      final repo = _FakeAuthRepository();
      final cubit = _cubit(repo);

      await cubit.registerClienteEmpresa(
        email: 'a@b.co',
        password: 'Password123',
        razonSocial: 'Andina',
        nit: '900123456',
        nombreRepresentante: 'Laura',
        tenantId: 't',
        aceptaTerminos: true,
      );

      expect(cubit.state, isA<AuthRegistrationSuccess>());
      expect(repo.registrosEmpresa, hasLength(1));
    });
  });

  group('HU-M02-07 pantalla', () {
    Future<_FakeAuthRepository> abrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _FakeAuthRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider(
            create: (_) => _cubit(repo),
            child: const RegistroClienteEmpresaView(),
          ),
        ),
      );
      return repo;
    }

    Future<void> llenar(
      WidgetTester tester, {
      String nit = '900.123.456-7',
    }) async {
      await tester.enterText(
        find.byKey(const Key('razonSocial')),
        'Constructora Andina SAS',
      );
      await tester.enterText(find.byKey(const Key('nit')), nit);
      await tester.enterText(
        find.byKey(const Key('nombreRepresentante')),
        'Laura Gómez',
      );
      await tester.enterText(
        find.byKey(const Key('email')),
        'compras@andina.co',
      );
      await tester.enterText(find.byKey(const Key('password')), 'Secreta123!');
    }

    Future<void> enviar(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('crearCuentaEmpresa')));
      await tester.pump();
    }

    testWidgets('pide NIT, representante y credenciales; no pide sedes', (
      tester,
    ) async {
      await abrir(tester);

      expect(find.byKey(const Key('nit')), findsOneWidget);
      expect(find.byKey(const Key('nombreRepresentante')), findsOneWidget);
      expect(find.textContaining('SEDE'), findsNothing);

      await enviar(tester);
      expect(find.text('El NIT es obligatorio'), findsOneWidget);
      expect(
        find.text('El representante legal es obligatorio'),
        findsOneWidget,
      );
    });

    testWidgets('sin la casilla de términos no registra', (tester) async {
      final repo = await abrir(tester);
      await llenar(tester);

      await enviar(tester);

      expect(
        find.byKey(const Key('error_terminos_obligatorios')),
        findsOneWidget,
      );
      expect(repo.registrosEmpresa, isEmpty);
    });

    testWidgets('con todo válido registra con el NIT normalizado', (
      tester,
    ) async {
      final repo = await abrir(tester);
      await llenar(tester);
      await tester.tap(find.byKey(const Key('checkbox_aceptacion_terminos')));
      await tester.pump();

      await enviar(tester);
      await tester.pump();

      expect(repo.registrosEmpresa, hasLength(1));
      expect(repo.registrosEmpresa.single['nit'], '900123456-7');
      expect(
        repo.registrosEmpresa.single['tenantId'],
        RegistroClienteEmpresaView.defaultTenantId,
      );
      expect(find.text('¡Cuenta de Empresa Creada!'), findsOneWidget);
    });
  });
}
