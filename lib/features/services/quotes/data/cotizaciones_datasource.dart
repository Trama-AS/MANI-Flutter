import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';

import '../domain/cotizacion.dart';

/// Fuente de las cotizaciones, separada para probar la pantalla sin red.
abstract interface class FuenteCotizaciones {
  Future<List<Cotizacion>> listar(String solicitudId);

  Future<Cotizacion> emitir(
    String solicitudId, {
    required String valorManoObra,
    required String valorMateriales,
  });

  Future<Cotizacion> responder(
    String cotizacionId,
    DecisionCotizacion decision, {
    String? texto,
  });
}

/// Cotizaciones por el Gateway a Core (SCRUM-865 y SCRUM-867). El tenant, el
/// aliado y el cliente salen del JWT; la app solo envía ids e importes.
class GatewayFuenteCotizaciones implements FuenteCotizaciones {
  GatewayFuenteCotizaciones(this._gateway);

  static String rutaSolicitud(String solicitudId) =>
      '/api/v1/core/solicitudes/$solicitudId/cotizaciones';
  static String rutaDecision(String cotizacionId, DecisionCotizacion d) =>
      '/api/v1/core/cotizaciones/$cotizacionId/${d.ruta}';

  final GatewayClient _gateway;

  @override
  Future<List<Cotizacion>> listar(String solicitudId) => _llamar(() async {
    final res = await _gateway.get(rutaSolicitud(solicitudId));
    final lista = res['cotizaciones'];
    if (lista is! List) {
      throw const FormatException('Respuesta de Core sin "cotizaciones"');
    }
    return lista
        .whereType<Map>()
        .map((e) => Cotizacion.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  });

  @override
  Future<Cotizacion> emitir(
    String solicitudId, {
    required String valorManoObra,
    required String valorMateriales,
  }) => _llamar(() async {
    // Se envían como texto: Core rechaza más de dos decimales en vez de
    // redondearlos, así que la app no convierte a double antes de enviar.
    final res = await _gateway.postJson(rutaSolicitud(solicitudId), {
      'valorManoObra': valorManoObra,
      'valorMateriales': valorMateriales,
    });
    return _cotizacionDe(res);
  });

  @override
  Future<Cotizacion> responder(
    String cotizacionId,
    DecisionCotizacion decision, {
    String? texto,
  }) => _llamar(() async {
    final cuerpo = <String, dynamic>{
      if (texto != null && texto.trim().isNotEmpty)
        (decision == DecisionCotizacion.rechazar ? 'motivo' : 'comentario'):
            texto.trim(),
    };
    final res = await _gateway.postJson(
      rutaDecision(cotizacionId, decision),
      cuerpo,
    );
    return _cotizacionDe(res);
  });

  static Cotizacion _cotizacionDe(Map<String, dynamic> res) {
    final c = res['cotizacion'];
    if (c is! Map) {
      throw const FormatException('Respuesta de Core sin "cotizacion"');
    }
    return Cotizacion.fromJson(Map<String, dynamic>.from(c));
  }

  static Future<T> _llamar<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on GatewayException catch (e) {
      throw mapearGateway(e);
    } on FormatException catch (e) {
      throw CotizacionFailure(CotizacionErrorTipo.desconocido, e.message);
    }
  }

  /// Un 5xx no se disfraza de éxito ni de lista vacía (T2). Los 400 y 409
  /// conservan el texto de Core sin el prefijo `MANI-COT-*`.
  static CotizacionFailure mapearGateway(GatewayException e) {
    final status = e.statusCode;
    final detalle = _sinCodigo(e.message);
    if (status == null) {
      return CotizacionFailure(CotizacionErrorTipo.sinConexion, detalle);
    }
    return switch (status) {
      401 => CotizacionFailure(CotizacionErrorTipo.sinSesion, detalle),
      403 => CotizacionFailure(CotizacionErrorTipo.sinPermiso, detalle),
      404 => CotizacionFailure(CotizacionErrorTipo.noEncontrada, detalle),
      400 ||
      422 => CotizacionFailure(CotizacionErrorTipo.datosInvalidos, detalle),
      409 => CotizacionFailure(CotizacionErrorTipo.conflicto, detalle),
      >= 500 => CotizacionFailure(
        CotizacionErrorTipo.servicioNoDisponible,
        detalle,
      ),
      _ => CotizacionFailure(CotizacionErrorTipo.desconocido, detalle),
    };
  }

  static String? _sinCodigo(String mensaje) {
    final limpio = mensaje.replaceFirst(RegExp(r'^MANI-[A-Z]+-\w+:\s*'), '');
    if (limpio.trim().isEmpty) return null;
    return '${limpio[0].toUpperCase()}${limpio.substring(1)}';
  }
}
