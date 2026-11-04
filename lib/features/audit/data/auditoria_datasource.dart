import 'package:mani/core/network/gateway_client.dart';

import '../domain/evento_transaccion.dart';

/// Fuente del registro de transacciones, separada para probar la pantalla sin red.
abstract interface class FuenteAuditoria {
  /// Eventos del tenant, con paginación por cursor ([despuesDe] es el id del
  /// último evento que ya se tiene) y filtro opcional por pago.
  Future<List<EventoTransaccion>> listar({
    String? despuesDe,
    String? pagoId,
    int limite,
  });
}

/// Auditoría de transacciones por el Gateway a Core (SCRUM-889). Solo la ve el
/// administrador del tenant: Core responde 403 a cualquier otro rol y 404 por
/// los pagos de otro tenant. El tenant sale del JWT, nunca de la consulta.
class GatewayFuenteAuditoria implements FuenteAuditoria {
  GatewayFuenteAuditoria(this._gateway);

  static const ruta = '/api/v1/core/auditoria/transacciones';

  final GatewayClient _gateway;

  @override
  Future<List<EventoTransaccion>> listar({
    String? despuesDe,
    String? pagoId,
    int limite = 50,
  }) async {
    final res = await _gateway.get(
      ruta,
      queryParameters: {
        'limite': limite.toString(),
        'despuesDe': ?despuesDe,
        'pagoId': ?pagoId,
      },
    );
    final lista = res['eventos'];
    if (lista is! List) {
      throw const FormatException('Respuesta de Core sin "eventos"');
    }
    return [
      for (final e in lista)
        EventoTransaccion.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
  }
}
