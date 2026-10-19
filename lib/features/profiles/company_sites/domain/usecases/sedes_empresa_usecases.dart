import 'package:mani/features/profiles/company_sites/domain/entities/sede_empresa.dart';

class SedeEmpresaFailure implements Exception {
  const SedeEmpresaFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class ISedesEmpresaRepository {
  Future<List<SedeEmpresa>> listarSedes(String clienteId);
  Future<SedeEmpresa> agregarSede(String clienteId, NuevaSedeEmpresa sede);
}

class ListarSedesEmpresaUseCase {
  const ListarSedesEmpresaUseCase(this.repository);
  final ISedesEmpresaRepository repository;

  Future<List<SedeEmpresa>> call(String clienteId) {
    if (clienteId.trim().isEmpty) {
      throw const SedeEmpresaFailure(
        'El identificador del cliente es obligatorio.',
      );
    }
    return repository.listarSedes(clienteId.trim());
  }
}

class AgregarSedeEmpresaUseCase {
  const AgregarSedeEmpresaUseCase(this.repository);
  final ISedesEmpresaRepository repository;

  Future<SedeEmpresa> call(String clienteId, NuevaSedeEmpresa sede) {
    if (clienteId.trim().isEmpty) {
      throw const SedeEmpresaFailure(
        'El identificador del cliente es obligatorio.',
      );
    }
    if (sede.nombre.trim().isEmpty) {
      throw const SedeEmpresaFailure('El nombre de la sede es obligatorio.');
    }
    if (sede.direccion.trim().isEmpty) {
      throw const SedeEmpresaFailure('La dirección de la sede es obligatoria.');
    }
    if (sede.zonaId.trim().isEmpty) {
      throw const SedeEmpresaFailure(
        'La zona geográfica de la sede es obligatoria.',
      );
    }
    return repository.agregarSede(clienteId.trim(), sede);
  }
}
