import 'package:mani/core/network/gateway_client.dart';

import '../domain/aviso.dart';

/// Fuente de la bandeja de avisos, separada para probar la pantalla sin red.
abstract interface class FuenteAvisos {
  /// Avisos de la sesión, del más reciente al más antiguo.
  Future<BandejaAvisos> listar({int limite});
}

/// Bandeja por el Gateway a Core (SCRUM-882 y 884). El tenant, el usuario y el
/// rol salen del JWT: la app nunca dice de quién son los avisos.
class GatewayFuenteAvisos implements FuenteAvisos {
  GatewayFuenteAvisos(this._gateway);

  static const ruta = '/api/v1/core/profiles/me/inbox';

  final GatewayClient _gateway;

  @override
  Future<BandejaAvisos> listar({int limite = 50}) async {
    final res = await _gateway.get(
      ruta,
      queryParameters: {'limit': limite.toString()},
    );
    return BandejaAvisos.fromJson(res);
  }
}
