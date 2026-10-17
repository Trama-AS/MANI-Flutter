import 'package:mani/core/network/gateway_client.dart';

/// Acceso a `/profiles/me/unavailability` de Core a través del API Gateway
/// (SCRUM-855). Devuelve el JSON tal cual; el repositorio lo traduce.
abstract interface class DisponibilidadRemoteDataSource {
  Future<Map<String, dynamic>> listar();
  Future<Map<String, dynamic>> crear(Map<String, dynamic> cuerpo);
  Future<Map<String, dynamic>> editar(String id, Map<String, dynamic> cuerpo);
  Future<void> eliminar(String id);
}

class GatewayDisponibilidadDataSource
    implements DisponibilidadRemoteDataSource {
  GatewayDisponibilidadDataSource(this.gateway);

  static const ruta = '/api/v1/core/profiles/me/unavailability';

  final GatewayClient gateway;

  @override
  Future<Map<String, dynamic>> listar() => gateway.get(ruta);

  @override
  Future<Map<String, dynamic>> crear(Map<String, dynamic> cuerpo) =>
      gateway.postJson(ruta, cuerpo);

  @override
  Future<Map<String, dynamic>> editar(String id, Map<String, dynamic> cuerpo) =>
      gateway.patch('$ruta/${Uri.encodeComponent(id)}', cuerpo);

  @override
  Future<void> eliminar(String id) =>
      gateway.delete('$ruta/${Uri.encodeComponent(id)}');
}
