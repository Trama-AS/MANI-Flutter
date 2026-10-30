import 'package:mani/core/network/gateway_client.dart';

import '../domain/tarifa.dart';

/// Fuente del tarifario de referencia (M-10), separada para probar las
/// pantallas sin red.
abstract interface class FuenteTarifas {
  Future<List<Tarifa>> activas();

  Future<List<Tarifa>> historial(String categoriaId);

  Future<Tarifa> crear(String categoriaId, DatosTarifa datos);

  /// Crea la versión siguiente de [tarifaId] (la deja REEMPLAZADA).
  Future<Tarifa> editar(String tarifaId, DatosTarifa datos);

  Future<ReferenciaTarifa> referencia(String solicitudId);

  /// [desde] y [hasta] en `YYYY-MM-DD`, ambos inclusive.
  Future<ReporteFueraDeRango> reporteFueraDeRango(String desde, String hasta);
}

/// Tarifario por el Gateway a Core (SCRUM-885, 886 y 887). Tenant, usuario y
/// rol salen del JWT; la app nunca los envía.
class GatewayFuenteTarifas implements FuenteTarifas {
  GatewayFuenteTarifas(this._gateway);

  static const rutaTarifas = '/api/v1/core/tarifas';
  static String rutaHistorial(String categoriaId) =>
      '$rutaTarifas/categorias/$categoriaId/historial';
  static String rutaReferencia(String solicitudId) =>
      '/api/v1/core/solicitudes/$solicitudId/tarifa-referencia';
  static const rutaReporte =
      '/api/v1/core/reportes/cotizaciones-fuera-de-rango';

  final GatewayClient _gateway;

  @override
  Future<List<Tarifa>> activas() async =>
      _lista((await _gateway.get(rutaTarifas))['tarifas']);

  @override
  Future<List<Tarifa>> historial(String categoriaId) async =>
      _lista((await _gateway.get(rutaHistorial(categoriaId)))['versiones']);

  @override
  Future<Tarifa> crear(String categoriaId, DatosTarifa datos) async => _tarifa(
    await _gateway.postJson(rutaTarifas, {
      'categoriaId': categoriaId,
      ...datos.toJson(),
    }),
  );

  @override
  Future<Tarifa> editar(String tarifaId, DatosTarifa datos) async =>
      _tarifa(await _gateway.put('$rutaTarifas/$tarifaId', datos.toJson()));

  @override
  Future<ReferenciaTarifa> referencia(String solicitudId) async =>
      ReferenciaTarifa.fromJson(
        await _gateway.get(rutaReferencia(solicitudId)),
      );

  @override
  Future<ReporteFueraDeRango> reporteFueraDeRango(
    String desde,
    String hasta,
  ) async => ReporteFueraDeRango.fromJson(
    await _gateway.get(
      rutaReporte,
      queryParameters: {'desde': desde, 'hasta': hasta},
    ),
  );

  static List<Tarifa> _lista(Object? valor) => [
    for (final t in (valor as List? ?? const []))
      Tarifa.fromJson(Map<String, dynamic>.from(t as Map)),
  ];

  static Tarifa _tarifa(Map<String, dynamic> res) {
    final t = res['tarifa'];
    if (t is! Map) {
      throw const FormatException('Respuesta de Core sin "tarifa"');
    }
    return Tarifa.fromJson(Map<String, dynamic>.from(t));
  }
}
