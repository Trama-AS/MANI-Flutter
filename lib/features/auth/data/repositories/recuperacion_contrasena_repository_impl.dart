import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/auth/data/datasources/recuperacion_contrasena_remote_data_source.dart';
import 'package:mani/features/auth/domain/entities/auth_failure.dart';
import 'package:mani/features/auth/domain/repositories/i_recuperacion_contrasena_repository.dart';

/// Convierte los errores del Gateway en [AuthFailure] con el mensaje que ya
/// viene listo para mostrar.
class RecuperacionContrasenaRepositoryImpl
    implements IRecuperacionContrasenaRepository {
  const RecuperacionContrasenaRepositoryImpl({required this.remoteDataSource});

  final IRecuperacionContrasenaRemoteDataSource remoteDataSource;

  @override
  Future<void> solicitarEnlace({
    required String email,
    required String tenantSlug,
  }) => _traducir(
    () => remoteDataSource.solicitar(email: email, tenantSlug: tenantSlug),
  );

  @override
  Future<void> restablecer({
    required String accessToken,
    required String newPassword,
    required String tenantSlug,
  }) => _traducir(
    () => remoteDataSource.restablecer(
      accessToken: accessToken,
      newPassword: newPassword,
      tenantSlug: tenantSlug,
    ),
  );

  Future<void> _traducir(Future<void> Function() accion) async {
    try {
      await accion();
    } on GatewayException catch (e) {
      throw AuthFailure(e.message);
    } catch (e) {
      throw AuthFailure('Error en la recuperación de contraseña: $e');
    }
  }
}
