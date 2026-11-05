import 'package:mani/features/profiles/direct_employees/domain/entities/empleado_directo.dart';

class EmpleadoDirectoFailure implements Exception {
  const EmpleadoDirectoFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class IEmpleadosDirectosRepository {
  Future<EmpleadoDirectoCreado> registrarEmpleadoDirecto(
    NuevoEmpleadoDirecto nuevoEmpleado,
  );
}

class RegistrarEmpleadoDirectoUseCase {
  const RegistrarEmpleadoDirectoUseCase(this.repository);

  final IEmpleadosDirectosRepository repository;

  Future<EmpleadoDirectoCreado> call(NuevoEmpleadoDirecto nuevoEmpleado) {
    if (nuevoEmpleado.nombreCompleto.trim().isEmpty) {
      throw const EmpleadoDirectoFailure('El nombre completo es obligatorio.');
    }
    if (nuevoEmpleado.email.trim().isEmpty) {
      throw const EmpleadoDirectoFailure(
        'El correo electrónico es obligatorio.',
      );
    }
    if (nuevoEmpleado.password.length < 8) {
      throw const EmpleadoDirectoFailure(
        'La contraseña debe tener al menos 8 caracteres.',
      );
    }
    if (nuevoEmpleado.telefono.trim().isEmpty) {
      throw const EmpleadoDirectoFailure('El teléfono es obligatorio.');
    }
    if (!tiposDocumentoEmpleado.contains(nuevoEmpleado.tipoDocumento)) {
      throw const EmpleadoDirectoFailure(
        'Selecciona el tipo de documento de identidad.',
      );
    }
    if (nuevoEmpleado.numeroDocumento.trim().isEmpty) {
      throw const EmpleadoDirectoFailure(
        'El número de documento es obligatorio.',
      );
    }
    final documento = nuevoEmpleado.documento;
    if (documento.tipoContenido == null) {
      throw const EmpleadoDirectoFailure(
        'La copia del documento debe ser PDF, JPG o PNG.',
      );
    }
    if (documento.bytes.isEmpty) {
      throw const EmpleadoDirectoFailure(
        'El documento seleccionado está vacío.',
      );
    }
    if (documento.bytes.length > maxBytesDocumentoIdentidad) {
      throw const EmpleadoDirectoFailure('El documento no puede superar 5 MB.');
    }
    if (nuevoEmpleado.categoriaIds.isEmpty) {
      throw const EmpleadoDirectoFailure(
        'Debes asignar al menos una categoría operativa al empleado directo.',
      );
    }
    return repository.registrarEmpleadoDirecto(nuevoEmpleado);
  }
}
