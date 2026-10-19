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
    if (nuevoEmpleado.categoriaIds.isEmpty) {
      throw const EmpleadoDirectoFailure(
        'Debes asignar al menos una categoría operativa al empleado directo.',
      );
    }
    return repository.registrarEmpleadoDirecto(nuevoEmpleado);
  }
}
