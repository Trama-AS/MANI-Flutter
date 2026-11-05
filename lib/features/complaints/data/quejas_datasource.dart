import 'package:mani/core/network/gateway_client.dart';

import '../domain/queja.dart';

/// Fuente de las quejas (M-12), separada para probar las pantallas sin red.
abstract interface class FuenteQuejas {
  Future<Queja> registrar(
    String solicitudId, {
    required MotivoQueja motivo,
    required String descripcion,
  });

  Future<List<Queja>> mias();

  Future<List<Queja>> delTenant({EstadoQueja? estado});

  Future<Queja> detalle(String quejaId);

  Future<Queja> cambiarEstado(
    String quejaId,
    EstadoQueja estado, {
    String? nota,
  });
}

/// Quejas por el Gateway a Core (SCRUM-895 y 896). Tenant, usuario y rol
/// salen del JWT: el cliente solo alcanza sus quejas y el administrador las de
/// su tenant, y eso lo decide Core.
class GatewayFuenteQuejas implements FuenteQuejas {
  GatewayFuenteQuejas(this._gateway);

  static const rutaQuejas = '/api/v1/core/quejas';
  static String rutaRegistrar(String solicitudId) =>
      '/api/v1/core/solicitudes/$solicitudId/quejas';

  final GatewayClient _gateway;

  @override
  Future<Queja> registrar(
    String solicitudId, {
    required MotivoQueja motivo,
    required String descripcion,
  }) async => _queja(
    await _gateway.postJson(rutaRegistrar(solicitudId), {
      'motivo': motivo.valor,
      'descripcion': descripcion.trim(),
    }),
  );

  @override
  Future<List<Queja>> mias() async =>
      _lista((await _gateway.get('$rutaQuejas/mias'))['quejas']);

  @override
  Future<List<Queja>> delTenant({EstadoQueja? estado}) async => _lista(
    (await _gateway.get(
      rutaQuejas,
      queryParameters: {'estado': ?estado?.valor},
    ))['quejas'],
  );

  @override
  Future<Queja> detalle(String quejaId) async =>
      _queja(await _gateway.get('$rutaQuejas/$quejaId'));

  @override
  Future<Queja> cambiarEstado(
    String quejaId,
    EstadoQueja estado, {
    String? nota,
  }) async => _queja(
    await _gateway.patch('$rutaQuejas/$quejaId/estado', {
      'estado': estado.valor,
      'nota': ?nota,
    }),
  );

  static List<Queja> _lista(Object? valor) => [
    for (final q in (valor as List? ?? const []))
      Queja.fromJson(Map<String, dynamic>.from(q as Map)),
  ];

  static Queja _queja(Map<String, dynamic> res) {
    final q = res['queja'];
    if (q is! Map) throw const FormatException('Respuesta de Core sin "queja"');
    return Queja.fromJson(Map<String, dynamic>.from(q));
  }
}
