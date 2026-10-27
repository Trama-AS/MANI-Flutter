import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';

import '../domain/aliado_elegible.dart';

/// Fuente de los aliados elegibles, separada para probar la pantalla sin red.
abstract interface class FuenteElegibles {
  Future<ListaElegibles> listar(String solicitudId, {TipoAliado? tipo});
}

/// Aliados elegibles por el Gateway a Dispatch (HU-M05-03/05 y SCRUM-1401):
/// `GET /api/v1/dispatch/requests/{id}/eligible-allies`. Zona y categoría
/// salen del contexto de Core y el tenant del JWT; la app solo filtra por
/// tipo.
class GatewayFuenteElegibles implements FuenteElegibles {
  GatewayFuenteElegibles(this._gateway);

  /// Una sola página amplia: la lista se muestra en el orden del backend.
  static const tamanoPagina = 50;

  static String ruta(String solicitudId) =>
      '/api/v1/dispatch/requests/${Uri.encodeComponent(solicitudId)}/eligible-allies';

  final GatewayClient _gateway;

  @override
  Future<ListaElegibles> listar(String solicitudId, {TipoAliado? tipo}) async {
    final Map<String, dynamic> res;
    try {
      res = await _gateway.get(
        ruta(solicitudId),
        queryParameters: {
          'page': '1',
          'pageSize': '$tamanoPagina',
          if (tipo != null) 'tipo': tipo.valor,
        },
      );
    } on GatewayException catch (e) {
      throw mapearGateway(e);
    }
    return ListaElegibles.fromJson(res);
  }

  /// Un 5xx no se disfraza de lista vacía: se informa que no se pudo
  /// consultar.
  static ElegiblesFailure mapearGateway(GatewayException e) {
    final codigo = e.cuerpo?['code'];
    final status = e.statusCode;
    if (status == null) {
      return ElegiblesFailure(ElegiblesErrorTipo.sinConexion, e.message);
    }
    if (status == 400 || codigo == 'MANI-DSP-400') {
      return ElegiblesFailure(ElegiblesErrorTipo.tipoInvalido, e.message);
    }
    if (status == 401) {
      return ElegiblesFailure(ElegiblesErrorTipo.sinSesion, e.message);
    }
    if (status == 403) {
      return ElegiblesFailure(ElegiblesErrorTipo.noPermitido, e.message);
    }
    if (status == 404) {
      return ElegiblesFailure(ElegiblesErrorTipo.noEncontrada, e.message);
    }
    if (status >= 500) {
      return ElegiblesFailure(
        ElegiblesErrorTipo.servicioNoDisponible,
        e.message,
      );
    }
    return ElegiblesFailure(ElegiblesErrorTipo.desconocido, e.message);
  }
}
