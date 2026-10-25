import 'package:mani/features/auth/domain/repositories/i_auth_repository.dart';

/// Registro de cliente empresa (HU-M02-07): cuenta con NIT y representante
/// legal, separada de la administración de sitios.
class RegisterClienteEmpresaUseCase {
  final IAuthRepository repository;

  RegisterClienteEmpresaUseCase(this.repository);

  Future<Map<String, dynamic>> call({
    required String email,
    required String password,
    required String razonSocial,
    required String nit,
    required String nombreRepresentante,
    required String tenantId,
    String? telefono,
  }) {
    return repository.registrarClienteEmpresa(
      email: email,
      password: password,
      razonSocial: razonSocial,
      nit: nit,
      nombreRepresentante: nombreRepresentante,
      tenantId: tenantId,
      telefono: telefono,
    );
  }
}
