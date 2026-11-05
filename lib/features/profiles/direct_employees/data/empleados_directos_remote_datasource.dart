import 'dart:convert';

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
/// (`POST /api/v1/core/allies/employees`, multipart) para US-02.1.5 (SCRUM-850 / SCRUM-1376).
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
    final nombre = nuevoEmpleado.nombreCompleto.trim();
    // El Gateway recibe multipart: la copia del documento viaja como archivo y las categorías como lista JSON.
    final campos = <String, String>{
      'email': nuevoEmpleado.email.trim(),
      'password': nuevoEmpleado.password,
      'fullName': nombre,
      'phone': nuevoEmpleado.telefono.trim(),
      'documentType': nuevoEmpleado.tipoDocumento,
      'documentNumber': nuevoEmpleado.numeroDocumento.trim(),
      'categoriaIds': jsonEncode(nuevoEmpleado.categoriaIds),
    };
    final documento = nuevoEmpleado.documento;

    final respuesta = await gateway.postMultipart(
      rutaEmpleadosDirectos,
      campos: campos,
      archivos: [
        ArchivoMultipart(
          campo: 'documento_identidad',
          nombre: documento.nombre,
          bytes: documento.bytes,
          tipoContenido: documento.tipoContenido,
        ),
      ],
    );
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
