import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/messaging/data/mensajes_datasource.dart';
import 'package:mani/features/messaging/domain/mensaje.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

Map<String, dynamic> _mensajeJson(
  String id, {
  bool mio = false,
  String rol = 'ALLY',
}) => {
  'id': id,
  'solicitudId': 'sol-1',
  'contenido': 'hola $id',
  'creadoEn': '2026-10-27T15:30:00.000Z',
  'remitente': {'rol': rol},
  'mio': mio,
};

/// HU-M09-02: la app habla con Core por el Gateway y nunca envía remitente, tenant ni rol.
void main() {
  late List<http.Request> alGateway;
  late http.Response Function(http.Request) responder;

  GatewayFuenteMensajes fuente() {
    final gateway = GatewayClient(
      baseUrl: 'http://gateway.local',
      tokenProvider: () async => 'jwt-de-prueba',
      correlationId: () => 'corr-test',
      initialRetryDelay: Duration.zero,
      httpClient: MockClient((r) async {
        alGateway.add(r);
        return responder(r);
      }),
    );
    return GatewayFuenteMensajes(gateway);
  }

  setUp(() {
    alGateway = [];
    responder = (_) => http.Response(
      jsonEncode({
        'mensajes': [_mensajeJson('m1')],
      }),
      200,
      headers: _json,
    );
  });

  group('enviar', () {
    test(
      'POST con el texto y la clave de idempotencia; sin remitente, tenant ni rol',
      () async {
        responder = (_) => http.Response(
          jsonEncode({'mensaje': _mensajeJson('m1', mio: true)}),
          201,
          headers: _json,
        );

        await fuente().enviar('sol-1', 'hola', claveIdempotencia: 'clave-1');

        final r = alGateway.single;
        expect(r.method, 'POST');
        expect(
          r.url.toString(),
          'http://gateway.local/api/v1/core/solicitudes/sol-1/mensajes',
        );
        expect(r.headers['Authorization'], 'Bearer jwt-de-prueba');
        expect(jsonDecode(utf8.decode(r.bodyBytes)), {
          'contenido': 'hola',
          'claveIdempotencia': 'clave-1',
        });
      },
    );

    test('un 200 (reintento con la misma clave) también es éxito', () async {
      responder = (_) => http.Response(
        jsonEncode({'mensaje': _mensajeJson('m1', mio: true)}),
        200,
        headers: _json,
      );
      await fuente().enviar('sol-1', 'hola', claveIdempotencia: 'k');
    });
  });

  group('listar', () {
    test('primera carga: GET sin cursor, y el mensaje se interpreta', () async {
      final lista = await fuente().listar('sol-1');

      final r = alGateway.single;
      expect(r.method, 'GET');
      expect(r.url.path, '/api/v1/core/solicitudes/sol-1/mensajes');
      expect(r.url.queryParameters, isEmpty);
      expect(lista.single.id, 'm1');
      expect(lista.single.esMio, isFalse);
      expect(lista.single.rolRemitente, 'ALLY');
      expect(lista.single.etiquetaRemitente, 'Aliado');
      expect(lista.single.creadoEn, isNotNull);
    });

    test('consulta incremental: envía despuesDe', () async {
      await fuente().listar('sol-1', despuesDe: 'm0');
      expect(alGateway.single.url.queryParameters, {'despuesDe': 'm0'});
    });

    test('una respuesta sin "mensajes" no se toma como lista vacía', () async {
      responder = (_) =>
          http.Response(jsonEncode({'otra': 1}), 200, headers: _json);
      await expectLater(
        fuente().listar('sol-1'),
        throwsA(
          isA<MensajeFailure>().having(
            (f) => f.tipo,
            'tipo',
            MensajeErrorTipo.desconocido,
          ),
        ),
      );
    });
  });

  group('errores', () {
    Future<MensajeFailure> fallo(int status, Map<String, Object?> body) async {
      responder = (_) =>
          http.Response(jsonEncode(body), status, headers: _json);
      try {
        await fuente().enviar('sol-1', 'hola', claveIdempotencia: 'k');
      } on MensajeFailure catch (f) {
        return f;
      }
      fail('debía lanzar MensajeFailure');
    }

    test('C3: 404 y 403 son definitivos; no se reintenta el hilo', () async {
      final noExiste = await fallo(404, {
        'error': 'MANI-MSG-404: solicitud no encontrada',
      });
      final prohibido = await fallo(403, {'error': 'x'});
      final sinSesion = await fallo(401, {'error': 'x'});

      expect(noExiste.tipo, MensajeErrorTipo.noEncontrado);
      expect(prohibido.tipo, MensajeErrorTipo.sinPermiso);
      expect(sinSesion.tipo, MensajeErrorTipo.sinSesion);
      expect([noExiste, prohibido, sinSesion].every((f) => f.definitivo), true);
    });

    test('un 409 es servicio cerrado: se lee pero no se escribe', () async {
      final f = await fallo(409, {
        'error': 'MANI-MSG-409E: la solicitud en estado FINALIZADA no admite',
        'code': 'MANI-MSG-409E',
      });
      expect(f.tipo, MensajeErrorTipo.servicioCerrado);
      expect(f.definitivo, isFalse);
      expect(f.mensajeUsuario, contains('ya no admite mensajes nuevos'));
    });

    test('un 400 muestra el texto de Core sin el código', () async {
      final f = await fallo(400, {
        'error':
            'MANI-MSG-400: el mensaje debe tener entre 1 y 1000 caracteres',
      });
      expect(f.tipo, MensajeErrorTipo.datosInvalidos);
      expect(
        f.mensajeUsuario,
        'el mensaje debe tener entre 1 y 1000 caracteres',
      );
    });

    test('un 5xx no filtra detalles internos y no es definitivo', () async {
      final f = await fallo(500, {'error': 'TypeError at line 42'});
      expect(f.tipo, MensajeErrorTipo.servicioNoDisponible);
      expect(f.mensajeUsuario, isNot(contains('TypeError')));
      expect(f.definitivo, isFalse);
    });

    test('sin red se explica y no es definitivo', () async {
      responder = (_) => throw http.ClientException('sin red');
      await expectLater(
        fuente().enviar('sol-1', 'hola', claveIdempotencia: 'k'),
        throwsA(
          isA<MensajeFailure>()
              .having((f) => f.tipo, 'tipo', MensajeErrorTipo.sinConexion)
              .having((f) => f.definitivo, 'definitivo', false),
        ),
      );
    });

    test('el correlationId de Core queda en el fallo', () async {
      final f = await fallo(503, {'error': 'x', 'correlationId': 'corr-core'});
      expect(f.correlationId, isNotNull);
    });
  });

  test('GatewayException desconocida cae a desconocido', () {
    final f = GatewayFuenteMensajes.mapearGateway(
      const GatewayException(message: 'x', statusCode: 418),
    );
    expect(f.tipo, MensajeErrorTipo.desconocido);
  });
}
