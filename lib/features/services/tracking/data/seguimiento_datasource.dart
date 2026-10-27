import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';

import '../domain/solicitud_seguimiento.dart';

/// Fuente del seguimiento, separada para probar la pantalla sin red.
abstract interface class FuenteSeguimiento {
  Future<List<SolicitudSeguimiento>> listar();
}

/// Solicitudes del cliente por el Gateway a Core (HU-M07-04 / SCRUM-871):
/// `GET /api/v1/core/solicitudes/me`. El cliente y el tenant salen del JWT;
/// la app no envía ningún id.
class GatewayFuenteSeguimiento implements FuenteSeguimiento {
  GatewayFuenteSeguimiento(this._gateway);

  static const ruta = '/api/v1/core/solicitudes/me';

  final GatewayClient _gateway;

  @override
  Future<List<SolicitudSeguimiento>> listar() async {
    final Map<String, dynamic> res;
    try {
      res = await _gateway.get(ruta);
    } on GatewayException catch (e) {
      throw mapearGateway(e);
    }
    final lista = res['solicitudes'];
    // Un 200 sin la lista es una respuesta mal formada, no «sin solicitudes» (T2):
    // se informa el error para que el cliente pueda reintentar.
    if (lista is! List) {
      throw const SeguimientoFailure(
        SeguimientoErrorTipo.desconocido,
        'Respuesta de Core sin "solicitudes"',
      );
    }
    return lista
        .whereType<Map>()
        .map((e) => SolicitudSeguimiento.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// Un 5xx no se disfraza de lista vacía (T2): se informa que no se pudo
  /// consultar.
  static SeguimientoFailure mapearGateway(GatewayException e) {
    final codigo = e.cuerpo?['code'];
    final status = e.statusCode;
    if (status == null) {
      return SeguimientoFailure(SeguimientoErrorTipo.sinConexion, e.message);
    }
    if (status == 401 || codigo == 'MANI-SOL-401') {
      return SeguimientoFailure(SeguimientoErrorTipo.sinSesion, e.message);
    }
    if (status == 403 || codigo == 'MANI-SOL-403C') {
      return SeguimientoFailure(SeguimientoErrorTipo.noEsCliente, e.message);
    }
    if (status >= 500) {
      return SeguimientoFailure(
        SeguimientoErrorTipo.servicioNoDisponible,
        e.message,
      );
    }
    return SeguimientoFailure(SeguimientoErrorTipo.desconocido, e.message);
  }
}
