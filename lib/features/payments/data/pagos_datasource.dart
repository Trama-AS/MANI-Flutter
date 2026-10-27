import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';

import '../domain/pago.dart';

/// Fuente de los pagos del sandbox, separada para probar la pantalla sin red.
abstract interface class FuentePagos {
  Future<Pago> pagar(
    String cotizacionId, {
    required EscenarioPago escenario,
    required String claveIdempotencia,
  });

  Future<ComprobantePago> comprobante(String pagoId);
}

/// Pagos del sandbox por el Gateway a Core (SCRUM-1432). El tenant, el cliente y
/// el rol salen del JWT; la app envía la cotización, el escenario simulado y una
/// clave de idempotencia. Nunca envía monto ni datos de tarjeta.
class GatewayFuentePagos implements FuentePagos {
  GatewayFuentePagos(this._gateway);

  static const rutaPagos = '/api/v1/core/pagos';
  static String rutaComprobante(String pagoId) =>
      '$rutaPagos/$pagoId/comprobante';

  final GatewayClient _gateway;

  @override
  Future<Pago> pagar(
    String cotizacionId, {
    required EscenarioPago escenario,
    required String claveIdempotencia,
  }) => _llamar(() async {
    final res = await _gateway.postJson(rutaPagos, {
      'cotizacionId': cotizacionId,
      'escenario': escenario.valor,
      'claveIdempotencia': claveIdempotencia,
    });
    final pago = res['pago'];
    if (pago is! Map) {
      throw const FormatException('Respuesta de Core sin "pago"');
    }
    return Pago.fromJson(Map<String, dynamic>.from(pago));
  });

  @override
  Future<ComprobantePago> comprobante(String pagoId) => _llamar(() async {
    final res = await _gateway.get(rutaComprobante(pagoId));
    final c = res['comprobante'];
    if (c is! Map) {
      throw const FormatException('Respuesta de Core sin "comprobante"');
    }
    return ComprobantePago.fromJson(Map<String, dynamic>.from(c));
  });

  static Future<T> _llamar<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on GatewayException catch (e) {
      throw mapearGateway(e);
    } on FormatException {
      throw const PagoFailure(PagoErrorTipo.desconocido);
    }
  }

  /// Un fallo del proveedor (502/504) conserva el texto de Core, que dice que no
  /// se realizó ningún cobro: el cliente no debe dudar de si le cobraron.
  static PagoFailure mapearGateway(GatewayException e) {
    final status = e.statusCode;
    final correlationId =
        e.correlationId ?? e.cuerpo?['correlationId'] as String?;
    final textoCore = _sinCodigo((e.cuerpo?['error'] as String?) ?? e.message);
    PagoFailure f(PagoErrorTipo tipo, {String? detalle}) =>
        PagoFailure(tipo, detalle: detalle, correlationId: correlationId);

    if (status == null) return f(PagoErrorTipo.sinConexion);
    return switch (status) {
      401 => f(PagoErrorTipo.sinSesion),
      403 => f(PagoErrorTipo.sinPermiso),
      404 => f(PagoErrorTipo.noEncontrado),
      400 || 422 => f(PagoErrorTipo.datosInvalidos, detalle: textoCore),
      409 => f(PagoErrorTipo.conflicto, detalle: textoCore),
      502 || 504 => f(PagoErrorTipo.proveedorSinRespuesta, detalle: textoCore),
      >= 500 => f(PagoErrorTipo.servicioNoDisponible),
      _ => f(PagoErrorTipo.desconocido),
    };
  }

  static final _prefijo = RegExp(r'^MANI-PAG-\w+:\s*');
  static String _sinCodigo(String texto) => texto.replaceFirst(_prefijo, '');
}
