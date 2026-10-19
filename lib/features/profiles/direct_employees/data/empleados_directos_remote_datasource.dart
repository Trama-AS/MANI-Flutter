import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/profiles/direct_employees/domain/entities/empleado_directo.dart';
import 'package:mani/features/profiles/direct_employees/domain/usecases/registrar_empleado_directo_usecase.dart';

abstract class IEmpleadosDirectosRemoteDataSource {
  Future<EmpleadoDirectoCreado> registrarEmpleadoDirecto(
    NuevoEmpleadoDirecto nuevoEmpleado,
  );
}

/// Datasource HTTP que comunica con Core Node a través del API Gateway
/// (`POST /api/v1/allies/direct-employees`) para US-02.1.5 (SCRUM-850).
/// Cumple ADR-0027: cero acceso directo a PostgREST o Supabase Storage.
class EmpleadosDirectosRemoteDataSource
    implements IEmpleadosDirectosRemoteDataSource {
  const EmpleadosDirectosRemoteDataSource({required this.gateway});

  final GatewayClient gateway;

  static const String rutaEmpleadosDirectos = '/api/v1/core/allies/employees';

  @override
  Future<EmpleadoDirectoCreado> registrarEmpleadoDirecto(
    NuevoEmpleadoDirecto nuevoEmpleado,
  ) async {
    final payload = <String, dynamic>{
      'email': nuevoEmpleado.email.trim(),
      'password': nuevoEmpleado.password,
      'nombreCompleto': nuevoEmpleado.nombreCompleto.trim(),
      'fullName': nuevoEmpleado.nombreCompleto.trim(),
      'nombre': nuevoEmpleado.nombreCompleto.trim(),
      'categoriaIds': nuevoEmpleado.categoriaIds,
      if (nuevoEmpleado.categoriaIds.isNotEmpty)
        'categoriaId': nuevoEmpleado.categoriaIds.first,
      if (nuevoEmpleado.telefono != null &&
          nuevoEmpleado.telefono!.trim().isNotEmpty)
        'telefono': nuevoEmpleado.telefono!.trim(),
    };

    final respuesta = await gateway.postJson(rutaEmpleadosDirectos, payload);
    return EmpleadoDirectoCreado.fromJson(respuesta);
  }
}

class EmpleadosDirectosRepositoryImpl implements IEmpleadosDirectosRepository {
  const EmpleadosDirectosRepositoryImpl({required this.remoteDataSource});

  final IEmpleadosDirectosRemoteDataSource remoteDataSource;

  @override
  Future<EmpleadoDirectoCreado> registrarEmpleadoDirecto(
    NuevoEmpleadoDirecto nuevoEmpleado,
  ) async {
    try {
      return await remoteDataSource.registrarEmpleadoDirecto(nuevoEmpleado);
    } on GatewayException catch (e) {
      throw EmpleadoDirectoFailure(e.message);
    } on EmpleadoDirectoFailure {
      rethrow;
    } catch (_) {
      throw const EmpleadoDirectoFailure(
        'No fue posible registrar el empleado directo en este momento.',
      );
    }
  }
}
