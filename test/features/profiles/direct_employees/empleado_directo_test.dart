import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/platform/selector_documento.dart';
import 'package:mani/core/platform/selector_fotos.dart';
import 'package:mani/features/profiles/direct_employees/data/empleados_directos_remote_datasource.dart';
import 'package:mani/features/profiles/direct_employees/domain/entities/empleado_directo.dart';
import 'package:mani/features/profiles/direct_employees/domain/usecases/registrar_empleado_directo_usecase.dart';
import 'package:mani/features/profiles/direct_employees/presentation/bloc/empleado_directo_cubit.dart';
import 'package:mani/features/profiles/direct_employees/presentation/pages/registrar_empleado_directo_page.dart';

class _SelectorFalso implements SelectorDocumento {
  _SelectorFalso(this.archivo);
  final ArchivoLocal? archivo;
  int llamadas = 0;

  @override
  Future<ArchivoLocal?> seleccionar() async {
    llamadas++;
    return archivo;
  }
}

final _pdf = DocumentoIdentidad(
  nombre: 'cedula.pdf',
  bytes: Uint8List.fromList(utf8.encode('%PDF-1.4 copia')),
);

NuevoEmpleadoDirecto _nuevo({
  String telefono = '3001234567',
  String tipoDocumento = 'CC',
  String numeroDocumento = '1020304050',
  DocumentoIdentidad? documento,
  List<String> categoriaIds = const ['cat-1', 'cat-2'],
}) => NuevoEmpleadoDirecto(
  email: ' tecnico@empresa.co ',
  password: 'Password123!',
  nombreCompleto: ' Pedro Gómez ',
  categoriaIds: categoriaIds,
  telefono: telefono,
  tipoDocumento: tipoDocumento,
  numeroDocumento: numeroDocumento,
  documento: documento ?? _pdf,
);

const _respuestaCore = {
  'message': 'Empleado directo registrado exitosamente.',
  'correlationId': 'corr-1376',
  'tenantId': 'tenant-a',
  'employee': {
    'id': 'ally-1376',
    'usuarioId': 'user-1376',
    'tenantId': 'tenant-a',
    'fullName': 'Pedro Gómez',
    'email': 'tecnico@empresa.co',
    'phone': '3001234567',
    'documentType': 'CC',
    'documentNumber': '1020304050',
    'categoriaIds': ['cat-1', 'cat-2'],
    'tipo': 'EMPLEADO_DIRECTO',
    'estadoVerificacion': 'VERIFICADO',
  },
};

GatewayClient _gateway(
  Future<http.Response> Function(http.Request) responder,
) => GatewayClient(
  baseUrl: 'http://gateway.local',
  tokenProvider: () async => 'jwt-admin-token',
  correlationId: () => 'corr-1376',
  httpClient: MockClient(responder),
);

RegistrarEmpleadoDirectoUseCase _useCase(GatewayClient gateway) =>
    RegistrarEmpleadoDirectoUseCase(
      EmpleadosDirectosRepositoryImpl(
        remoteDataSource: EmpleadosDirectosRemoteDataSource(gateway: gateway),
      ),
    );

http.Response _ok() => http.Response(
  jsonEncode(_respuestaCore),
  201,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('SCRUM-1376 (RF-05) — Registrar empleado directo', () {
    test(
      'Datasource envía multipart con los datos obligatorios y la copia del documento, y lee la respuesta de Core',
      () async {
        late http.Request capturada;
        final useCase = _useCase(
          _gateway((req) async {
            capturada = req;
            return _ok();
          }),
        );

        final res = await useCase(_nuevo());

        expect(capturada.method, 'POST');
        expect(
          capturada.url.toString(),
          'http://gateway.local/api/v1/core/allies/employees',
        );
        expect(capturada.headers['Authorization'], 'Bearer jwt-admin-token');
        expect(
          capturada.headers['content-type'],
          startsWith('multipart/form-data'),
        );
        final cuerpo = capturada.body;
        expect(cuerpo, contains('name="fullName"'));
        expect(cuerpo, contains('Pedro Gómez'));
        expect(cuerpo, contains('name="phone"'));
        expect(cuerpo, contains('name="documentType"'));
        expect(cuerpo, contains('name="documentNumber"'));
        expect(cuerpo, contains('["cat-1","cat-2"]'));
        expect(
          cuerpo,
          contains('name="documento_identidad"; filename="cedula.pdf"'),
        );
        expect(cuerpo, contains('content-type: application/pdf'));
        expect(cuerpo, isNot(contains('tenantId')));

        expect(res.id, 'ally-1376');
        expect(res.nombreCompleto, 'Pedro Gómez');
        expect(res.telefono, '3001234567');
        expect(res.estadoVerificacion, 'VERIFICADO');
        expect(res.esEmpleadoDirecto, isTrue);
        expect(res.categoriaIds, ['cat-1', 'cat-2']);
      },
    );

    test(
      'el caso de uso exige teléfono, documento de identidad y categorías',
      () {
        final useCase = _useCase(_gateway((_) async => _ok()));
        expect(
          () => useCase(_nuevo(telefono: ' ')),
          throwsA(isA<EmpleadoDirectoFailure>()),
        );
        expect(
          () => useCase(_nuevo(tipoDocumento: '')),
          throwsA(isA<EmpleadoDirectoFailure>()),
        );
        expect(
          () => useCase(_nuevo(tipoDocumento: 'NIT')),
          throwsA(isA<EmpleadoDirectoFailure>()),
        );
        expect(
          () => useCase(_nuevo(numeroDocumento: '  ')),
          throwsA(isA<EmpleadoDirectoFailure>()),
        );
        expect(
          () => useCase(_nuevo(categoriaIds: const [])),
          throwsA(isA<EmpleadoDirectoFailure>()),
        );
      },
    );

    test(
      'rechaza copias que no son PDF, JPG o PNG, vacías o de más de 5 MB',
      () {
        final useCase = _useCase(_gateway((_) async => _ok()));
        expect(
          () => useCase(
            _nuevo(
              documento: DocumentoIdentidad(
                nombre: 'rut.docx',
                bytes: Uint8List(10),
              ),
            ),
          ),
          throwsA(isA<EmpleadoDirectoFailure>()),
        );
        expect(
          () => useCase(
            _nuevo(
              documento: DocumentoIdentidad(
                nombre: 'a.png',
                bytes: Uint8List(0),
              ),
            ),
          ),
          throwsA(isA<EmpleadoDirectoFailure>()),
        );
        expect(
          () => useCase(
            _nuevo(
              documento: DocumentoIdentidad(
                nombre: 'grande.jpg',
                bytes: Uint8List(maxBytesDocumentoIdentidad + 1),
              ),
            ),
          ),
          throwsA(isA<EmpleadoDirectoFailure>()),
        );
      },
    );

    test('acepta exactamente 5 MB y las extensiones jpg, jpeg y png', () async {
      final useCase = _useCase(_gateway((_) async => _ok()));
      for (final nombre in ['a.jpg', 'a.JPEG', 'a.png']) {
        await useCase(
          _nuevo(
            documento: DocumentoIdentidad(
              nombre: nombre,
              bytes: Uint8List(maxBytesDocumentoIdentidad),
            ),
          ),
        );
      }
    });

    test('un 409 de Core llega al usuario como falla con su mensaje', () async {
      final useCase = _useCase(
        _gateway(
          (_) async => http.Response(
            jsonEncode({
              'error':
                  'Ya existe un aliado registrado con ese número de documento',
              'code': 'DOCUMENT_ALREADY_REGISTERED',
              'correlationId': 'c',
            }),
            409,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await expectLater(
        useCase(_nuevo()),
        throwsA(
          isA<EmpleadoDirectoFailure>().having(
            (e) => e.message,
            'message',
            contains('número de documento'),
          ),
        ),
      );
    });

    Future<EmpleadoDirectoCubit> montar(
      WidgetTester tester, {
      required GatewayClient gateway,
      required _SelectorFalso selector,
    }) async {
      final cubit = EmpleadoDirectoCubit(registrarUseCase: _useCase(gateway));
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: RegistrarEmpleadoDirectoPage(
              selectorDocumento: selector,
              categoriasDisponibles: const {
                'cat-plomeria': 'Plomería y Redes Hidráulicas',
              },
            ),
          ),
        ),
      );
      return cubit;
    }

    Future<void> llenarFormulario(WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const Key('input_nombre_empleado_directo')),
        'Laura Directa',
      );
      await tester.enterText(
        find.byKey(const Key('input_email_empleado_directo')),
        'directo@tenant.co',
      );
      await tester.enterText(
        find.byKey(const Key('input_password_empleado_directo')),
        'Password123!',
      );
      await tester.enterText(
        find.byKey(const Key('input_telefono_empleado_directo')),
        '3001234567',
      );
      await tester.enterText(
        find.byKey(const Key('input_numero_documento_empleado_directo')),
        '1020304050',
      );
      final tipo = find.byKey(
        const Key('input_tipo_documento_empleado_directo'),
      );
      await tester.ensureVisible(tipo);
      await tester.pumpAndSettle();
      await tester.tap(tipo);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cédula de ciudadanía').last);
      await tester.pumpAndSettle();
      final chk = find.byKey(const Key('chk_categoria_cat-plomeria'));
      await tester.ensureVisible(chk);
      await tester.pumpAndSettle();
      await tester.tap(chk);
      await tester.pump();
    }

    testWidgets(
      'la pantalla registra con la copia del documento y muestra el estado VERIFICADO inmediato',
      (tester) async {
        var peticiones = 0;
        final selector = _SelectorFalso(
          ArchivoLocal(nombre: 'cedula.pdf', bytes: _pdf.bytes),
        );
        final cubit = await montar(
          tester,
          gateway: _gateway((_) async {
            peticiones++;
            return _ok();
          }),
          selector: selector,
        );

        await llenarFormulario(tester);
        final adjuntar = find.byKey(
          const Key('btn_adjuntar_documento_empleado_directo'),
        );
        await tester.ensureVisible(adjuntar);
        await tester.tap(adjuntar);
        await tester.pumpAndSettle();
        expect(selector.llamadas, 1);
        expect(find.text('cedula.pdf'), findsOneWidget);

        final btn = find.byKey(const Key('btn_registrar_empleado_directo'));
        await tester.ensureVisible(btn);
        await tester.pumpAndSettle();
        await tester.tap(btn);
        await tester.pumpAndSettle();

        expect(peticiones, 1);
        expect(
          find.byKey(const Key('card_empleado_directo_creado')),
          findsOneWidget,
        );
        expect(find.textContaining('Estado: VERIFICADO'), findsOneWidget);
        await cubit.close();
      },
    );

    testWidgets(
      'sin la copia del documento la pantalla avisa y no envía nada',
      (tester) async {
        var peticiones = 0;
        final cubit = await montar(
          tester,
          gateway: _gateway((_) async {
            peticiones++;
            return _ok();
          }),
          selector: _SelectorFalso(null),
        );

        await llenarFormulario(tester);
        final btn = find.byKey(const Key('btn_registrar_empleado_directo'));
        await tester.ensureVisible(btn);
        await tester.pumpAndSettle();
        await tester.tap(btn);
        await tester.pumpAndSettle();

        expect(peticiones, 0);
        expect(
          find.byKey(const Key('error_documento_empleado_directo')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('card_empleado_directo_creado')),
          findsNothing,
        );
        await cubit.close();
      },
    );

    testWidgets('un archivo de más de 5 MB se rechaza en la pantalla', (
      tester,
    ) async {
      var peticiones = 0;
      final selector = _SelectorFalso(
        ArchivoLocal(
          nombre: 'grande.pdf',
          bytes: Uint8List(maxBytesDocumentoIdentidad + 1),
        ),
      );
      final cubit = await montar(
        tester,
        gateway: _gateway((_) async {
          peticiones++;
          return _ok();
        }),
        selector: selector,
      );

      await llenarFormulario(tester);
      final adjuntar = find.byKey(
        const Key('btn_adjuntar_documento_empleado_directo'),
      );
      await tester.ensureVisible(adjuntar);
      await tester.tap(adjuntar);
      await tester.pumpAndSettle();
      expect(find.text('El archivo no puede superar 5 MB'), findsOneWidget);

      final btn = find.byKey(const Key('btn_registrar_empleado_directo'));
      await tester.ensureVisible(btn);
      await tester.pumpAndSettle();
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(peticiones, 0);
      await cubit.close();
    });
  });
}
