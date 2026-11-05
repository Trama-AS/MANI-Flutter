import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/auth/domain/entities/user_entity.dart';
import 'package:mani/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:mani/features/auth/domain/usecases/login_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_aliado_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_cliente_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_empresa_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_cliente_empresa_usecase.dart';
import 'package:mani/features/auth/presentation/bloc/auth_cubit.dart';
import 'package:mani/features/auth/presentation/widgets/documento_legal_modal.dart';
import 'package:mani/features/auth/presentation/widgets/terminos_condiciones_section.dart';
import 'package:mani/features/auth/domain/entities/registro_cliente_empresa.dart';

class _FakeAuthRepository implements IAuthRepository {
  int llamadasRegistro = 0;

  @override
  Future<UserEntity> signInWithEmail({
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> registrarClientePersonaNatural({
    required String email,
    required String password,
    required String nombreCompleto,
    required String tenantId,
    String? telefono,
    String? direccionHogar,
  }) async {
    llamadasRegistro++;
    return {'success': true, 'usuario_id': 'u-1'};
  }

  @override
  Future<Map<String, dynamic>> registrarClienteEmpresa(
    RegistroClienteEmpresa datos,
  ) async {
    llamadasRegistro++;
    return {'success': true, 'usuario_id': 'u-2'};
  }

  @override
  Future<Map<String, dynamic>> registrarAliadoPersonaNatural({
    required String email,
    required String password,
    required String nombreCompleto,
    required String tenantId,
    required String categoriaId,
    required List<Map<String, String>> documentosKYC,
  }) async {
    llamadasRegistro++;
    return {'success': true, 'estado_verificacion': 'PENDIENTE'};
  }

  @override
  Future<Map<String, dynamic>> registrarAliadoEmpresa({
    required String email,
    required String password,
    required String razonSocial,
    required String nit,
    required String tenantId,
    required String nombreRepresentante,
    String? docRepresentante,
    String? telefonoContacto,
    String? categoriaId,
    required List<Map<String, String>> documentosKYC,
  }) async {
    llamadasRegistro++;
    return {'success': true, 'estado_verificacion': 'PENDIENTE'};
  }

  @override
  Future<void> signOut() async {}
}

void main() {
  group(
    'SCRUM-856 (US-02.3.2) — Aceptación de Términos y Condiciones y Habeas Data',
    () {
      testWidgets(
        'US-02.3.2: muestra checkbox desmarcado, enlaces legales y mensaje de error cuando es obligatorio',
        (tester) async {
          bool aceptado = false;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    return TerminosCondicionesSection(
                      aceptaTerminos: aceptado,
                      mostrarError: !aceptado,
                      onChanged: (val) => setState(() => aceptado = val),
                    );
                  },
                ),
              ),
            ),
          );

          final checkboxFinder = find.byKey(
            const Key('checkbox_aceptacion_terminos'),
          );
          expect(checkboxFinder, findsOneWidget);
          expect(tester.widget<Checkbox>(checkboxFinder).value, isFalse);
          expect(
            find.byKey(const Key('error_terminos_obligatorios')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('btn_ver_terminos')), findsOneWidget);
          expect(
            find.byKey(const Key('btn_ver_politica_datos')),
            findsOneWidget,
          );

          await tester.tap(checkboxFinder);
          await tester.pump();

          expect(aceptado, isTrue);
          expect(
            find.byKey(const Key('error_terminos_obligatorios')),
            findsNothing,
          );
        },
      );

      testWidgets(
        'US-02.3.2: abre el modal con el documento legal completo (v1.0 y Ley 1581) y permite aceptar tras leerlo',
        (tester) async {
          bool aceptado = false;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    return TerminosCondicionesSection(
                      aceptaTerminos: aceptado,
                      onChanged: (val) => setState(() => aceptado = val),
                    );
                  },
                ),
              ),
            ),
          );

          await tester.tap(find.byKey(const Key('btn_ver_terminos')));
          await tester.pumpAndSettle();

          expect(find.byType(DocumentoLegalModal), findsOneWidget);
          expect(
            find.textContaining('OBJETO Y ALCANCE DE LA PLATAFORMA MANI'),
            findsOneWidget,
          );

          // Cambiar a la pestaña de Política de Tratamiento de Datos (Ley 1581)
          await tester.tap(find.byKey(const Key('tab_politica_datos')));
          await tester.pumpAndSettle();

          expect(find.textContaining('LEY 1581 DE 2012'), findsOneWidget);

          // Confirmar lectura y aceptación desde el modal
          await tester.tap(
            find.byKey(const Key('btn_confirmar_lectura_terminos')),
          );
          await tester.pumpAndSettle();

          expect(aceptado, isTrue);
        },
      );

      test(
        'US-02.3.2: AuthCubit bloquea el registro de cliente, aliado y empresa si aceptaTerminos es false',
        () async {
          final repo = _FakeAuthRepository();
          final cubit = AuthCubit(
            loginUseCase: LoginUseCase(repo),
            registerClienteUseCase: RegisterClienteUseCase(repo),
            registerAliadoUseCase: RegisterAliadoUseCase(repo),
            registerEmpresaUseCase: RegisterEmpresaUseCase(repo),
            registerClienteEmpresaUseCase: RegisterClienteEmpresaUseCase(repo),
          );

          await cubit.registerCliente(
            email: 'cliente@mani.co',
            password: 'Password123',
            nombreCompleto: 'Cliente Prueba',
            tenantId: 'plomeria-express',
            aceptaTerminos: false,
          );
          expect(cubit.state, isA<AuthError>());
          expect(
            (cubit.state as AuthError).message,
            AuthCubit.mensajeTerminosObligatorios,
          );
          expect(repo.llamadasRegistro, 0);

          await cubit.registerAliado(
            email: 'aliado@mani.co',
            password: 'Password123',
            nombreCompleto: 'Aliado Prueba',
            tenantId: 'plomeria-express',
            categoriaId: 'cat-1',
            documentosKYC: const [],
            aceptaTerminos: false,
          );
          expect(repo.llamadasRegistro, 0);

          await cubit.registerEmpresa(
            email: 'empresa@mani.co',
            password: 'Password123',
            razonSocial: 'Empresa S.A.S.',
            nit: '900123456-1',
            tenantId: 'plomeria-express',
            nombreRepresentante: 'Representante Legal',
            documentosKYC: const [],
            aceptaTerminos: false,
          );
          expect(repo.llamadasRegistro, 0);

          await cubit.registerCliente(
            email: 'cliente@mani.co',
            password: 'Password123',
            nombreCompleto: 'Cliente Prueba',
            tenantId: 'plomeria-express',
            aceptaTerminos: true,
          );
          expect(cubit.state, isA<AuthRegistrationSuccess>());
          expect(repo.llamadasRegistro, 1);

          await cubit.close();
        },
      );
    },
  );
}
