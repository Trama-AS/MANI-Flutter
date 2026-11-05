import 'package:mani/features/auth/domain/repositories/i_recuperacion_contrasena_repository.dart';

/// Pide el enlace de recuperación al correo (HU-M02-10).
class SolicitarRecuperacionUseCase {
  SolicitarRecuperacionUseCase(this.repository);

  final IRecuperacionContrasenaRepository repository;

  Future<void> call({required String email, required String tenantSlug}) =>
      repository.solicitarEnlace(email: email, tenantSlug: tenantSlug);
}

/// Fija la contraseña nueva con el token del enlace (HU-M02-10).
class RestablecerContrasenaUseCase {
  RestablecerContrasenaUseCase(this.repository);

  final IRecuperacionContrasenaRepository repository;

  Future<void> call({
    required String accessToken,
    required String newPassword,
    required String tenantSlug,
  }) => repository.restablecer(
    accessToken: accessToken,
    newPassword: newPassword,
    tenantSlug: tenantSlug,
  );
}
