import 'package:mani/core/network/gateway_client.dart';

import '../domain/consulta_conversacion.dart';

/// Fuente de la consulta de conversaciones, separada para probar la pantalla sin red.
abstract interface class FuenteConversacionQueja {
  Future<ConversacionConsultada> consultar(
    String solicitudId, {
    required String motivo,
    String? quejaRef,
  });
}

/// Consulta de la conversación de un servicio para atender una queja, por el
/// Gateway a Core (SCRUM-883). Solo el administrador del tenant: Core responde 403
/// a cualquier otro rol y 404 si la solicitud no existe o es de otro tenant. Cada
/// consulta queda registrada; el actor sale del JWT.
class GatewayFuenteConversacionQueja implements FuenteConversacionQueja {
  GatewayFuenteConversacionQueja(this._gateway);

  static String ruta(String solicitudId) =>
      '/api/v1/core/solicitudes/$solicitudId/conversacion/consultas';

  final GatewayClient _gateway;

  @override
  Future<ConversacionConsultada> consultar(
    String solicitudId, {
    required String motivo,
    String? quejaRef,
  }) async {
    final res = await _gateway.postJson(ruta(solicitudId), {
      'motivo': motivo,
      if (quejaRef != null && quejaRef.isNotEmpty) 'quejaRef': quejaRef,
    });
    return ConversacionConsultada.fromJson(res);
  }
}
