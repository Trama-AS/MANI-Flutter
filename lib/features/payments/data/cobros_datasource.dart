import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';

import '../domain/cobros.dart';
import '../domain/pago.dart';
import 'pagos_datasource.dart';

/// Retención, liquidación y cobros del aliado (SCRUM-891 a 894), separada de
/// [FuentePagos] para probar cada pantalla sin red.
abstract interface class FuenteCobros {
  /// Retención del pago, para el cliente que pagó.
  Future<RetencionPago> retencion(String pagoId);

  /// Cobros del aliado de la sesión, del más reciente al más antiguo.
  Future<List<CobroAliado>> cobrosDelAliado();
}

/// Todo sale por el Gateway a Core. El tenant, el usuario y el rol salen del
/// JWT; la app no envía ni monto ni identificadores del aliado.
class GatewayFuenteCobros implements FuenteCobros {
  GatewayFuenteCobros(this._gateway);

  static const rutaCobros = '/api/v1/core/pagos/aliado';
  static String rutaRetencion(String pagoId) =>
      '${GatewayFuentePagos.rutaPagos}/$pagoId/retencion';

  final GatewayClient _gateway;

  @override
  Future<RetencionPago> retencion(String pagoId) => _llamar(() async {
    final res = await _gateway.get(rutaRetencion(pagoId));
    final r = res['retencion'];
    if (r is! Map) throw const FormatException('Respuesta sin "retencion"');
    return RetencionPago.fromJson(Map<String, dynamic>.from(r));
  });

  @override
  Future<List<CobroAliado>> cobrosDelAliado() => _llamar(() async {
    final res = await _gateway.get(rutaCobros);
    final lista = res['cobros'];
    if (lista is! List) throw const FormatException('Respuesta sin "cobros"');
    return lista
        .map((e) => CobroAliado.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  });

  static Future<T> _llamar<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on GatewayException catch (e) {
      throw GatewayFuentePagos.mapearGateway(e);
    } on FormatException {
      throw const PagoFailure(PagoErrorTipo.desconocido);
    }
  }
}
