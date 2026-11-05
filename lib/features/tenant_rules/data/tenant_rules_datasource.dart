import 'package:mani/core/network/gateway_client.dart';
import '../domain/regla_tenant.dart';

abstract interface class FuenteReglasTenant {
  Future<ReglaTenantVigente> getVigente();
  Future<List<ReglaTenantHistorialItem>> getHistorial();
  Future<ReglaTenantVigente> actualizar({
    required int expectedVersion,
    required ReglasOperativas reglas,
  });
}

class GatewayFuenteReglasTenant implements FuenteReglasTenant {
  GatewayFuenteReglasTenant(this._gateway);

  static const String rutaVigente = '/api/v1/core/tenant/rules';
  static const String rutaHistorial = '/api/v1/core/tenant/rules/history';

  final GatewayClient _gateway;

  @override
  Future<ReglaTenantVigente> getVigente() async {
    final res = await _gateway.get(rutaVigente);
    return ReglaTenantVigente.fromJson(res);
  }

  @override
  Future<List<ReglaTenantHistorialItem>> getHistorial() async {
    final res = await _gateway.get(rutaHistorial);
    final items = res['items'] as List<dynamic>? ?? [];
    return items
        .map(
          (i) => ReglaTenantHistorialItem.fromJson(i as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<ReglaTenantVigente> actualizar({
    required int expectedVersion,
    required ReglasOperativas reglas,
  }) async {
    final res = await _gateway.put(rutaVigente, {
      'expectedVersion': expectedVersion,
      'reglas': reglas.toJson(),
    });
    return ReglaTenantVigente.fromJson(res);
  }
}
