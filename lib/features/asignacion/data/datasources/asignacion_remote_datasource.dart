import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/utils/generador_id.dart';

/// Acceso crudo a Dispatch por el Gateway. Ni `tenant_id` ni `aliado_id`
/// viajan desde la app: Dispatch y Core los derivan del JWT. Los errores salen
/// como `GatewayException` y el repositorio los traduce por `code`.
abstract interface class AsignacionRemoteDataSource {
  /// Elementos de la bandeja (`items`), en el formato camelCase de Core.
  Future<List<Map<String, dynamic>>> listar();

  /// Respuesta de la aceptación: `requestId`, `status` e `isRetry`. No trae
  /// la solicitud; el repositorio la vuelve a leer de la bandeja.
  Future<Map<String, dynamic>> aceptar(String solicitudId);
  Future<void> rechazar(String solicitudId, String motivo, String? detalle);

  /// Solo para trazas (log estructurado); nunca se usa para autorizar.
  String? get tenantIdSesion;
}

/// Bandeja, aceptación y rechazo por `MANI-APIGateway` → `MANI-.NET`
/// (decisión 6A, SCRUM-1402/1403/1404). Reemplaza las RPC de la migración
/// `005_aceptar_rechazar_solicitud.sql`.
class GatewayAsignacionDataSource implements AsignacionRemoteDataSource {
  GatewayAsignacionDataSource(
    this._gateway, {
    String? Function()? tenantIdSesion,
    String Function()? generarClave,
  }) : _tenantIdSesion = tenantIdSesion,
       _generarClave = generarClave ?? nuevoUuid;

  static const ruta = '/api/v1/dispatch';
  static const rutaBandeja = '$ruta/offers/me';

  static String rutaAceptar(String solicitudId) =>
      '$ruta/requests/${Uri.encodeComponent(solicitudId)}/accept';

  static String rutaRechazar(String solicitudId) =>
      '$ruta/requests/${Uri.encodeComponent(solicitudId)}/reject';

  final GatewayClient _gateway;
  final String? Function()? _tenantIdSesion;
  final String Function() _generarClave;

  @override
  Future<List<Map<String, dynamic>>> listar() async {
    final res = await _gateway.get(rutaBandeja);
    final items = res['items'];
    // Un 200 sin la lista es una respuesta mal formada, no «bandeja vacía» (T2).
    if (items is! List) {
      throw const FormatException('Respuesta de Dispatch sin "items"');
    }
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  /// Una clave por toque: si el `GatewayClient` reintenta tras un 503 o una
  /// caída de red, Core reconoce el reintento y no asigna dos veces (1405).
  @override
  Future<Map<String, dynamic>> aceptar(String solicitudId) => _gateway.postJson(
    rutaAceptar(solicitudId),
    const {},
    headers: {GatewayClient.headerIdempotencyKey: _generarClave()},
  );

  /// El rechazo es idempotente en Dispatch (`ON CONFLICT DO NOTHING`), así
  /// que también puede reintentarse con su propia clave.
  @override
  Future<void> rechazar(String solicitudId, String motivo, String? detalle) =>
      _gateway.postJson(
        rutaRechazar(solicitudId),
        {'motivo': motivo, 'detalle': ?detalle},
        headers: {GatewayClient.headerIdempotencyKey: _generarClave()},
      );

  @override
  String? get tenantIdSesion => _tenantIdSesion?.call();
}
