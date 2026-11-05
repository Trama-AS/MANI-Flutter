abstract class IRecuperacionContrasenaRepository {
  Future<void> solicitarEnlace({
    required String email,
    required String tenantSlug,
  });

  Future<void> restablecer({
    required String accessToken,
    required String newPassword,
    required String tenantSlug,
  });
}
