import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/profiles/company_sites/domain/entities/sede_empresa.dart';
import 'package:mani/features/profiles/company_sites/domain/usecases/sedes_empresa_usecases.dart';

abstract class ISedesEmpresaRemoteDataSource {
  Future<List<SedeEmpresa>> listarSedes(String clienteId);
  Future<SedeEmpresa> agregarSede(String clienteId, NuevaSedeEmpresa sede);
}

/// Datasource HTTP para gestionar múltiples sitios de un cliente empresa
/// a través del API Gateway (`GET/POST /api/v1/clients/companies/:id/sites`,
/// US-02.2.2 / SCRUM-852, ADR-0027).
class SedesEmpresaRemoteDataSource implements ISedesEmpresaRemoteDataSource {
  const SedesEmpresaRemoteDataSource({required this.gateway});

  final GatewayClient gateway;

  static String rutaSedesCliente(String clienteId) =>
      '/api/v1/core/clients/$clienteId/sites';

  @override
  Future<List<SedeEmpresa>> listarSedes(String clienteId) async {
    final respuesta = await gateway.get(rutaSedesCliente(clienteId));
    // Core responde `{ clienteId, razonSocial, totalSitios, sitios: [...] }`.
    // `data` y `sites` quedan como respaldo por si alguna respuesta vieja
    // sigue usándolas; sin `sitios` la lista llegaba siempre vacía aunque el
    // cliente tuviera sedes.
    final raw =
        respuesta['sitios'] ??
        respuesta['data'] ??
        respuesta['sites'] ??
        const [];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(SedeEmpresa.fromJson)
          .toList();
    }
    return const [];
  }

  @override
  Future<SedeEmpresa> agregarSede(
    String clienteId,
    NuevaSedeEmpresa sede,
  ) async {
    final payload = <String, dynamic>{
      'nombre': sede.nombre.trim(),
      'direccion': sede.direccion.trim(),
      'zonaId': sede.zonaId.trim(),
      'reglas': <String, dynamic>{},
      if (sede.contactoNombre != null && sede.contactoNombre!.trim().isNotEmpty)
        'contactoNombre': sede.contactoNombre!.trim(),
      if (sede.contactoTelefono != null &&
          sede.contactoTelefono!.trim().isNotEmpty)
        'contactoTelefono': sede.contactoTelefono!.trim(),
    };

    final respuesta = await gateway.postJson(
      rutaSedesCliente(clienteId),
      payload,
    );
    // Core responde `{ message, correlationId, sitio: {...} }`.
    final cuerpo = respuesta['sitio'] ?? respuesta['data'];
    final data = cuerpo is Map<String, dynamic> ? cuerpo : respuesta;
    return SedeEmpresa.fromJson(data);
  }
}

class SedesEmpresaRepositoryImpl implements ISedesEmpresaRepository {
  const SedesEmpresaRepositoryImpl({required this.remoteDataSource});

  final ISedesEmpresaRemoteDataSource remoteDataSource;

  @override
  Future<List<SedeEmpresa>> listarSedes(String clienteId) async {
    try {
      return await remoteDataSource.listarSedes(clienteId);
    } on GatewayException catch (e) {
      throw SedeEmpresaFailure(e.message);
    } catch (_) {
      throw const SedeEmpresaFailure(
        'Error al consultar las sedes de la empresa.',
      );
    }
  }

  @override
  Future<SedeEmpresa> agregarSede(
    String clienteId,
    NuevaSedeEmpresa sede,
  ) async {
    try {
      return await remoteDataSource.agregarSede(clienteId, sede);
    } on GatewayException catch (e) {
      throw SedeEmpresaFailure(e.message);
    } catch (_) {
      throw const SedeEmpresaFailure('Error al registrar la nueva sede.');
    }
  }
}
