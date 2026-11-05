import 'dart:convert';
import 'dart:typed_data';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/session/guardas_ruta.dart';
import 'package:mani/core/session/rol_usuario.dart';
import 'package:mani/core/platform/guardador_archivo.dart';
import 'package:mani/features/payments/data/cobros_datasource.dart';
import 'package:mani/features/payments/data/pagos_datasource.dart';
import 'package:mani/features/payments/domain/cobros.dart';
import 'package:mani/features/payments/domain/pago.dart';
import 'package:mani/features/payments/presentation/pago_cubit.dart';
import 'package:mani/features/payments/presentation/pago_sandbox_page.dart';

Pago _pago({String estado = 'APROBADO', String? motivo}) => Pago(
  id: 'pago-1',
  cotizacionId: 'cot-1',
  monto: 150000.5,
  moneda: 'COP',
  estadoCrudo: estado,
  proveedor: 'mock',
  simulado: true,
  referenciaProveedor: 'mock-pay-x',
  motivo: motivo,
);

const _comprobante = ComprobantePago(
  numero: 'SIM-ABCDEF12',
  simulado: true,
  monto: 150000.5,
  moneda: 'COP',
  leyenda: 'COMPROBANTE DE PRUEBA · SANDBOX · SIN VALOR CONTABLE NI FISCAL',
);

/// Fuente en memoria: registra las llamadas y responde lo que se le indique.
class _FuenteFake implements FuentePagos {
  Pago respuesta = _pago();
  Object? falloPagar;
  Object? falloComprobante;
  Completer<void>? espera;
  final pagos =
      <({String cotizacion, EscenarioPago escenario, String clave})>[];
  final comprobantes = <String>[];

  @override
  Future<Pago> pagar(
    String cotizacionId, {
    required EscenarioPago escenario,
    required String claveIdempotencia,
  }) async {
    pagos.add((
      cotizacion: cotizacionId,
      escenario: escenario,
      clave: claveIdempotencia,
    ));
    await espera?.future;
    if (falloPagar != null) throw falloPagar!;
    return respuesta;
  }

  @override
  Future<ComprobantePago> comprobante(String pagoId) async {
    comprobantes.add(pagoId);
    if (falloComprobante != null) throw falloComprobante!;
    return _comprobante;
  }
}

class _GuardadorFalso implements GuardadorArchivo {
  _GuardadorFalso({this.resultado = true, this.falla});

  final bool resultado;
  final Object? falla;
  final guardados = <({String nombre, String texto, String tipo})>[];

  @override
  Future<bool> guardar({
    required String nombre,
    required Uint8List bytes,
    String tipoMime = 'application/octet-stream',
  }) async {
    if (falla != null) throw falla!;
    guardados.add((nombre: nombre, texto: utf8.decode(bytes), tipo: tipoMime));
    return resultado;
  }
}

class _CobrosFalsos implements FuenteCobros {
  final pedidas = <String>[];

  @override
  Future<List<CobroAliado>> cobrosDelAliado() async => const [];

  @override
  Future<RetencionPago> retencion(String pagoId) async {
    pedidas.add(pagoId);
    return const RetencionPago(
      pagoId: 'pago-1',
      monto: 150000.5,
      moneda: 'COP',
      estado: EstadoRetencion.retenida,
      simulada: true,
    );
  }
}

void main() {
  group('PagoCubit', () {
    test('C1: un pago aprobado trae su comprobante simulado', () async {
      final f = _FuenteFake();
      final cubit = PagoCubit(f, 'cot-1', generarClave: () => 'k1');

      await cubit.pagar();

      expect(cubit.state.fase, FasePago.resultado);
      expect(cubit.state.pago?.aprobado, isTrue);
      expect(cubit.state.comprobante?.simulado, isTrue);
      expect(f.pagos.single.cotizacion, 'cot-1');
      expect(f.pagos.single.escenario, EscenarioPago.aprobado);
      expect(f.comprobantes, ['pago-1']);
    });

    test(
      'un pago rechazado o pendiente se muestra y no pide comprobante',
      () async {
        for (final estado in ['RECHAZADO', 'PENDIENTE']) {
          final f = _FuenteFake()..respuesta = _pago(estado: estado);
          final cubit = PagoCubit(f, 'cot-1');
          await cubit.pagar();
          expect(cubit.state.pago?.estado, EstadoPago.desde(estado));
          expect(f.comprobantes, isEmpty, reason: estado);
          expect(cubit.state.comprobante, isNull);
        }
      },
    );

    test(
      'C2: si el pago falla vuelve al formulario con el error y sin pago',
      () async {
        final f = _FuenteFake()
          ..falloPagar = const PagoFailure(
            PagoErrorTipo.proveedorSinRespuesta,
            detalle: 'No se realizó ningún cobro',
            correlationId: 'corr-1',
          );
        final cubit = PagoCubit(f, 'cot-1');

        await cubit.pagar();

        expect(cubit.state.fase, FasePago.inicial);
        expect(cubit.state.pago, isNull);
        expect(cubit.state.error?.correlationId, 'corr-1');
        expect(
          cubit.state.error?.mensajeUsuario,
          contains('No se realizó ningún cobro'),
        );
      },
    );

    test(
      'un comprobante que no se pudo traer no esconde el pago aprobado',
      () async {
        final f = _FuenteFake()
          ..falloComprobante = const PagoFailure(
            PagoErrorTipo.servicioNoDisponible,
          );
        final cubit = PagoCubit(f, 'cot-1');

        await cubit.pagar();

        expect(cubit.state.pago?.aprobado, isTrue);
        expect(cubit.state.comprobante, isNull);
        expect(cubit.state.falloComprobante, isTrue);
      },
    );

    test('cada intento usa una clave de idempotencia nueva', () async {
      var n = 0;
      final f = _FuenteFake()..respuesta = _pago(estado: 'RECHAZADO');
      final cubit = PagoCubit(f, 'cot-1', generarClave: () => 'k${++n}');

      await cubit.pagar();
      await cubit.pagar();

      expect(f.pagos.map((p) => p.clave), ['k1', 'k2']);
    });

    test('un doble toque mientras se paga no envía otro pago', () async {
      final f = _FuenteFake()..espera = Completer<void>();
      final cubit = PagoCubit(f, 'cot-1');

      final primero = cubit.pagar();
      await cubit.pagar();
      cubit.elegirEscenario(EscenarioPago.rechazado);
      f.espera!.complete();
      await primero;

      expect(f.pagos, hasLength(1));
      expect(
        f.pagos.single.escenario,
        EscenarioPago.aprobado,
        reason: 'no se cambia el escenario en pleno pago',
      );
    });

    test('el escenario elegido es el que se envía', () async {
      final f = _FuenteFake();
      final cubit = PagoCubit(f, 'cot-1');

      cubit.elegirEscenario(EscenarioPago.timeout);
      await cubit.pagar();

      expect(f.pagos.single.escenario, EscenarioPago.timeout);
    });
  });

  group('PagoSandboxPage', () {
    Future<_FuenteFake> montar(
      WidgetTester tester, {
      double? total = 150000.5,
      _FuenteFake? fuente,
      FuenteCobros? cobros,
      GuardadorArchivo? guardador,
    }) async {
      // Pantalla alta: con el comprobante, la retención y la descarga el contenido no cabe en 600 px.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(tester.view.reset);
      final f = fuente ?? _FuenteFake();
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider(
            create: (_) => PagoCubit(f, 'cot-1', generarClave: () => 'k'),
            child: PagoSandboxPage(
              total: total,
              cobros: cobros,
              guardador: guardador,
            ),
          ),
        ),
      );
      return f;
    }

    testWidgets(
      'avisa que es un sandbox, no pide tarjeta y muestra el total de la cotización',
      (tester) async {
        await montar(tester);

        expect(find.byKey(const Key('aviso-sandbox')), findsOneWidget);
        expect(find.textContaining('SANDBOX · PAGO SIMULADO'), findsOneWidget);
        expect(
          find.byType(TextField),
          findsNothing,
          reason: 'sin campos de tarjeta',
        );
        expect(find.byKey(const Key('total-cotizacion')), findsOneWidget);
        expect(find.textContaining('150.000,50'), findsOneWidget);
      },
    );

    testWidgets('SCRUM-891: un pago aprobado muestra su retención simulada', (
      tester,
    ) async {
      final cobros = _CobrosFalsos();
      await montar(tester, cobros: cobros);
      await tester.tap(find.byKey(const Key('btn-pagar-sandbox')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('retencion-pago')), findsOneWidget);
      expect(find.byKey(const Key('leyenda-retencion')), findsOneWidget);
      expect(cobros.pedidas, ['pago-1']);
    });

    testWidgets(
      'SCRUM-891 C2: un pago rechazado no consulta ni muestra retención',
      (tester) async {
        final rechazado = _FuenteFake()..respuesta = _pago(estado: 'RECHAZADO');
        final cobros = _CobrosFalsos();
        await montar(tester, fuente: rechazado, cobros: cobros);
        await tester.tap(find.byKey(const Key('btn-pagar-sandbox')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('retencion-pago')), findsNothing);
        expect(cobros.pedidas, isEmpty);
      },
    );

    testWidgets(
      'SCRUM-890 C1: el comprobante se descarga como archivo con su leyenda de simulado',
      (tester) async {
        final g = _GuardadorFalso();
        await montar(tester, guardador: g);
        await tester.tap(find.byKey(const Key('btn-pagar-sandbox')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('btn-descargar-comprobante')),
        );
        await tester.ensureVisible(
          find.byKey(const Key('btn-descargar-comprobante')),
        );
        await tester.tap(find.byKey(const Key('btn-descargar-comprobante')));
        await tester.pumpAndSettle();

        final archivo = g.guardados.single;
        expect(archivo.nombre, 'comprobante-SIM-ABCDEF12.txt');
        expect(archivo.tipo, 'text/plain');
        expect(archivo.texto, contains('COMPROBANTE DE PAGO SIM-ABCDEF12'));
        expect(archivo.texto, contains('150000.50 COP'));
        expect(archivo.texto, contains('SIN VALOR CONTABLE NI FISCAL'));
        expect(find.text('Comprobante guardado.'), findsOneWidget);
      },
    );

    testWidgets(
      'SCRUM-890: si guardar falla lo dice; si se cancela no muestra nada; sin guardador no hay botón',
      (tester) async {
        final g = _GuardadorFalso(falla: StateError('x'));
        await montar(tester, guardador: g);
        await tester.tap(find.byKey(const Key('btn-pagar-sandbox')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('btn-descargar-comprobante')),
        );
        await tester.ensureVisible(
          find.byKey(const Key('btn-descargar-comprobante')),
        );
        await tester.tap(find.byKey(const Key('btn-descargar-comprobante')));
        await tester.pumpAndSettle();
        expect(find.textContaining('No pudimos guardar'), findsOneWidget);
      },
    );

    testWidgets('SCRUM-890: cancelar la descarga no muestra mensaje', (
      tester,
    ) async {
      final g = _GuardadorFalso(resultado: false);
      await montar(tester, guardador: g);
      await tester.tap(find.byKey(const Key('btn-pagar-sandbox')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('btn-descargar-comprobante')),
      );
      await tester.tap(find.byKey(const Key('btn-descargar-comprobante')));
      await tester.pumpAndSettle();
      expect(g.guardados, hasLength(1));
      expect(find.text('Comprobante guardado.'), findsNothing);
    });

    testWidgets('SCRUM-890: sin guardador no hay botón de descarga', (
      tester,
    ) async {
      await montar(tester);
      await tester.tap(find.byKey(const Key('btn-pagar-sandbox')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('btn-descargar-comprobante')), findsNothing);
    });

    testWidgets('sin total no inventa uno', (tester) async {
      await montar(tester, total: null);
      expect(find.byKey(const Key('total-cotizacion')), findsNothing);
    });

    testWidgets(
      'C1: paga y muestra el resultado como simulado, con el comprobante y su leyenda',
      (tester) async {
        final f = await montar(tester);

        await tester.tap(find.byKey(const Key('btn-pagar-sandbox')));
        await tester.pumpAndSettle();

        expect(f.pagos, hasLength(1));
        expect(find.byKey(const Key('resultado-pago')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('resultado-pago')),
            matching: find.text('Pago aprobado'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('pago-simulado')), findsOneWidget);
        expect(find.byKey(const Key('comprobante-pago')), findsOneWidget);
        expect(find.byKey(const Key('leyenda-comprobante')), findsOneWidget);
        expect(
          find.textContaining('SIN VALOR CONTABLE NI FISCAL'),
          findsOneWidget,
        );
      },
    );

    testWidgets('un rechazo muestra el motivo y no hay comprobante', (
      tester,
    ) async {
      final f = _FuenteFake()
        ..respuesta = _pago(
          estado: 'RECHAZADO',
          motivo: 'Fondos insuficientes (simulado)',
        );
      await montar(tester, fuente: f);

      await tester.tap(find.byKey(const Key('btn-pagar-sandbox')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('resultado-pago')),
          matching: find.text('Pago rechazado'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Fondos insuficientes'), findsOneWidget);
      expect(find.byKey(const Key('comprobante-pago')), findsNothing);
    });

    testWidgets(
      'C2: un fallo del proveedor muestra el mensaje accionable y el código de seguimiento, sin resultado',
      (tester) async {
        final f = _FuenteFake()
          ..falloPagar = const PagoFailure(
            PagoErrorTipo.proveedorSinRespuesta,
            detalle:
                'El proveedor de pagos no respondió a tiempo. No se realizó ningún cobro; inténtalo de nuevo.',
            correlationId: 'corr-abc',
          );
        await montar(tester, fuente: f);

        await tester.tap(find.byKey(const Key('btn-pagar-sandbox')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('error-pago')), findsOneWidget);
        expect(
          find.textContaining('No se realizó ningún cobro'),
          findsOneWidget,
        );
        expect(find.text('Código de seguimiento: corr-abc'), findsOneWidget);
        expect(find.byKey(const Key('resultado-pago')), findsNothing);
        expect(
          find.byKey(const Key('btn-pagar-sandbox')),
          findsOneWidget,
          reason: 'se puede reintentar',
        );
      },
    );

    testWidgets('el escenario elegido en la lista es el que se envía', (
      tester,
    ) async {
      final f = await montar(tester);

      await tester.tap(find.byKey(const Key('escenario-pago')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(EscenarioPago.pendiente.etiqueta).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-pagar-sandbox')));
      await tester.pumpAndSettle();

      expect(f.pagos.single.escenario, EscenarioPago.pendiente);
    });
  });

  group('Guarda de rol de la ruta de pago', () {
    test('/cliente/pagos/... lo abren el cliente y el admin de plataforma', () {
      expect(rolPuedeAbrir(RolUsuario.cliente, '/cliente/pagos/cot-1'), isTrue);
      expect(rolPuedeAbrir(RolUsuario.aliado, '/cliente/pagos/cot-1'), isFalse);
      expect(
        rolPuedeAbrir(RolUsuario.adminTenant, '/cliente/pagos/cot-1'),
        isFalse,
      );
      expect(
        rolPuedeAbrir(RolUsuario.adminPlataforma, '/cliente/pagos/cot-1'),
        isTrue,
      );
    });
  });
}
