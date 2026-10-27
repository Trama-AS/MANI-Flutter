import 'package:mani/features/auth/domain/entities/registro_cliente_empresa.dart';
import 'package:mani/features/auth/domain/repositories/i_auth_repository.dart';

/// Registro de cliente empresa (HU-M02-07): cuenta con NIT y representante
/// legal, separada de la administración de sitios.
class RegisterClienteEmpresaUseCase {
  final IAuthRepository repository;

  RegisterClienteEmpresaUseCase(this.repository);

  Future<Map<String, dynamic>> call(RegistroClienteEmpresa datos) =>
      repository.registrarClienteEmpresa(datos);
}
