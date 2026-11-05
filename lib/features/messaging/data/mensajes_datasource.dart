import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';

import '../domain/mensaje.dart';

/// Fuente de los mensajes del servicio, separada para probar la pantalla sin red.
abstract interface class FuenteMensajes {
  /// Guarda el mensaje de la sesión. Una misma [claveIdempotencia] no duplica.
  Future<void> enviar(
    String solicitudId,
    String contenido, {
    required String claveIdempotencia,
  });

  /// Sin [despuesDe], los últimos mensajes; con él, solo los posteriores.
  Future<List<Mensaje>> listar(String solicitudId, {String? despuesDe});
}

/// Mensajería por el Gateway a Core (SCRUM-881). El remitente, el tenant y el
/// rol salen del JWT: la app envía solo el texto y una clave de idempotencia.
class GatewayFuenteMensajes implements FuenteMensajes {
  GatewayFuenteMensajes(this._gateway);

  static String ruta(String solicitudId) =>
      '/api/v1/core/solicitudes/$solicitudId/mensajes';

  final GatewayClient _gateway;

  @override
  Future<void> enviar(
    String solicitudId,
    String contenido, {
    required String claveIdempotencia,
  }) => _llamar(() async {
    await _gateway.postJson(ruta(solicitudId), {
      'contenido': contenido,
      'claveIdempotencia': claveIdempotencia,
    });
  });

  @override
  Future<List<Mensaje>> listar(String solicitudId, {String? despuesDe}) =>
      _llamar(() async {
        final res = await _gateway.get(
          ruta(solicitudId),
          queryParameters: {'despuesDe': ?despuesDe},
        );
        final lista = res['mensajes'];
        if (lista is! List) {
          throw const FormatException('Respuesta de Core sin "mensajes"');
        }
        return [
          for (final m in lista)
            Mensaje.fromJson(Map<String, dynamic>.from(m as Map)),
        ];
      });

  static Future<T> _llamar<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on GatewayException catch (e) {
      throw mapearGateway(e);
    } on FormatException {
      throw const MensajeFailure(MensajeErrorTipo.desconocido);
    }
  }

  static MensajeFailure mapearGateway(GatewayException e) {
    final status = e.statusCode;
    final correlationId =
        e.correlationId ?? e.cuerpo?['correlationId'] as String?;
    final textoCore = _sinCodigo((e.cuerpo?['error'] as String?) ?? e.message);
    MensajeFailure f(MensajeErrorTipo tipo, {String? detalle}) =>
        MensajeFailure(tipo, detalle: detalle, correlationId: correlationId);

    if (status == null) return f(MensajeErrorTipo.sinConexion);
    return switch (status) {
      401 => f(MensajeErrorTipo.sinSesion),
      403 => f(MensajeErrorTipo.sinPermiso),
      404 => f(MensajeErrorTipo.noEncontrado),
      400 || 422 => f(MensajeErrorTipo.datosInvalidos, detalle: textoCore),
      409 => f(MensajeErrorTipo.servicioCerrado),
      >= 500 => f(MensajeErrorTipo.servicioNoDisponible),
      _ => f(MensajeErrorTipo.desconocido),
    };
  }

  static final _prefijo = RegExp(r'^MANI-MSG-\w+:\s*');
  static String _sinCodigo(String texto) => texto.replaceFirst(_prefijo, '');
}
