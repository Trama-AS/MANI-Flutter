import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/payments/data/pagos_datasource.dart';
import 'package:mani/features/payments/domain/pago.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

Map<String, dynamic> _pagoJson({String estado = 'APROBADO'}) => {
  'id': 'pago-1',
  'cotizacionId': 'cot-1',
  'monto': 150000.5,
  'moneda': 'COP',
  'estado': estado,
  'proveedor': 'mock',
  'simulado': true,
  'referenciaProveedor': 'mock-pay-x',
  'motivo': null,
};

/// HU-M11-01: la app paga por el Gateway hacia Core y nunca envía monto ni tarjeta.
void main() {
  late List<http.Request> alGateway;
  late http.Response Function(http.Request) responder;

  GatewayFuentePagos fuente() {
    final gateway = GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => 'jwt-de-prueba',
      correlationId: () => 'corr-test',
      httpClient: MockClient((r) async {
        alGateway.add(r);
        return responder(r);
      }),
    );
    return GatewayFuentePagos(gateway);
  }

  Map<String, dynamic> cuerpo() =>
      jsonDecode(utf8.decode(alGateway.single.bodyBytes))
          as Map<String, dynamic>;

  setUp(() {
    alGateway = [];
    responder = (_) =>
        http.Response(jsonEncode({'pago': _pagoJson()}), 201, headers: _json);
  });

  group('pagar', () {
    test(
      'POST /api/v1/core/pagos con la cotización, el escenario y la clave; sin monto ni tarjeta',
      () async {
        final pago = await fuente().pagar(
          'cot-1',
          escenario: EscenarioPago.rechazado,
          claveIdempotencia: 'clave-1',
        );

        final r = alGateway.single;
        expect(r.method, 'POST');
        expect(
          r.url.toString(),
          'http://gateway.local${GatewayFuentePagos.rutaPagos}',
        );
        expect(GatewayFuentePagos.rutaPagos, '/api/v1/core/pagos');
        expect(r.headers['Authorization'], 'Bearer jwt-de-prueba');
        expect(cuerpo(), {
          'cotizacionId': 'cot-1',
          'escenario': 'RECHAZADO',
          'claveIdempotencia': 'clave-1',
        });
        expect(pago.id, 'pago-1');
        expect(pago.aprobado, isTrue);
        expect(pago.simulado, isTrue);
      },
    );

    test('cada escenario viaja con el texto que Core espera', () async {
      expect(EscenarioPago.values.map((e) => e.valor), [
        'APROBADO',
        'RECHAZADO',
        'PENDIENTE',
        'TIMEOUT',
        'RESPUESTA_INVALIDA',
      ]);
    });

    test('una respuesta sin "pago" no se toma como éxito', () async {
      responder = (_) =>
          http.Response(jsonEncode({'otra': 1}), 201, headers: _json);
      await expectLater(
        fuente().pagar(
          'cot-1',
          escenario: EscenarioPago.aprobado,
          claveIdempotencia: 'k',
        ),
        throwsA(
          isA<PagoFailure>().having(
            (f) => f.tipo,
            'tipo',
            PagoErrorTipo.desconocido,
          ),
        ),
      );
    });
  });

  group('errores', () {
    Future<PagoFailure> fallo(int status, Map<String, Object?> body) async {
      responder = (_) =>
          http.Response(jsonEncode(body), status, headers: _json);
      try {
        await fuente().pagar(
          'cot-1',
          escenario: EscenarioPago.aprobado,
          claveIdempotencia: 'k',
        );
      } on PagoFailure catch (f) {
        return f;
      }
      fail('debía lanzar PagoFailure');
    }

    test(
      'C2: un 504 conserva el texto de Core que dice que no se cobró y el correlationId',
      () async {
        final f = await fallo(504, {
          'error':
              'MANI-PAG-504: el proveedor de pagos no respondió a tiempo. No se realizó ningún cobro; inténtalo de nuevo.',
          'code': 'MANI-PAG-504',
          'correlationId': 'corr-core-1',
        });

        expect(f.tipo, PagoErrorTipo.proveedorSinRespuesta);
        expect(f.mensajeUsuario, contains('No se realizó ningún cobro'));
        expect(f.mensajeUsuario, isNot(contains('MANI-PAG')));
        expect(f.correlationId, isNotNull);
      },
    );

    test('C2: un 502 también es proveedor sin respuesta válida', () async {
      final f = await fallo(502, {
        'error':
            'MANI-PAG-502: el proveedor de pagos no dio una respuesta válida. No se realizó ningún cobro.',
      });
      expect(f.tipo, PagoErrorTipo.proveedorSinRespuesta);
      expect(f.mensajeUsuario, contains('No se realizó ningún cobro'));
    });

    test('un 409 muestra el texto de Core sin el código', () async {
      final f = await fallo(409, {
        'error': 'MANI-PAG-409A: la cotización ya tiene un pago aprobado',
        'code': 'MANI-PAG-409A',
      });
      expect(f.tipo, PagoErrorTipo.conflicto);
      expect(f.mensajeUsuario, 'la cotización ya tiene un pago aprobado');
    });

    test('401, 403, 404, 400 y 503 se traducen a su tipo', () async {
      expect((await fallo(401, {'error': 'x'})).tipo, PagoErrorTipo.sinSesion);
      expect((await fallo(403, {'error': 'x'})).tipo, PagoErrorTipo.sinPermiso);
      expect(
        (await fallo(404, {'error': 'x'})).tipo,
        PagoErrorTipo.noEncontrado,
      );
      expect(
        (await fallo(400, {'error': 'MANI-PAG-400: dato inválido'})).tipo,
        PagoErrorTipo.datosInvalidos,
      );
      expect(
        (await fallo(503, {'error': 'x'})).tipo,
        PagoErrorTipo.servicioNoDisponible,
      );
    });

    test('un 5xx genérico no filtra detalles internos', () async {
      final f = await fallo(500, {'error': 'TypeError at line 42'});
      expect(f.mensajeUsuario, isNot(contains('TypeError')));
    });

    test('sin red se explica y avisa de consultar antes de repetir', () async {
      responder = (_) => throw http.ClientException('sin red');
      await expectLater(
        fuente().pagar(
          'cot-1',
          escenario: EscenarioPago.aprobado,
          claveIdempotencia: 'k',
        ),
        throwsA(
          isA<PagoFailure>().having(
            (f) => f.tipo,
            'tipo',
            PagoErrorTipo.sinConexion,
          ),
        ),
      );
    });
  });

  group('comprobante', () {
    test('GET del comprobante del pago, marcado como simulado', () async {
      responder = (_) => http.Response(
        jsonEncode({
          'comprobante': {
            'numero': 'SIM-ABCDEF12',
            'simulado': true,
            'leyenda': 'COMPROBANTE DE PRUEBA · SANDBOX',
            'monto': 150000.5,
            'moneda': 'COP',
            'fecha': '2026-10-26T20:00:00.000Z',
          },
        }),
        200,
        headers: _json,
      );

      final c = await fuente().comprobante('pago-1');

      expect(alGateway.single.method, 'GET');
      expect(
        alGateway.single.url.path,
        '/api/v1/core/pagos/pago-1/comprobante',
      );
      expect(c.numero, 'SIM-ABCDEF12');
      expect(c.simulado, isTrue);
      expect(c.leyenda, contains('SANDBOX'));
    });

    test('un 409 (pago no aprobado) es un conflicto', () async {
      responder = (_) => http.Response(
        jsonEncode({'error': 'MANI-PAG-409C: sin comprobante'}),
        409,
        headers: _json,
      );
      await expectLater(
        fuente().comprobante('pago-1'),
        throwsA(
          isA<PagoFailure>().having(
            (f) => f.tipo,
            'tipo',
            PagoErrorTipo.conflicto,
          ),
        ),
      );
    });
  });

  test('GatewayException sin cuerpo cae al mensaje del Gateway', () {
    final f = GatewayFuentePagos.mapearGateway(
      const GatewayException(
        message: 'No se pudo completar la solicitud (418).',
        statusCode: 418,
      ),
    );
    expect(f.tipo, PagoErrorTipo.desconocido);
  });
}
