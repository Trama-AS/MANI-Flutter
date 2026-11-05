import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/features/auth/domain/entities/auth_failure.dart';
import 'package:mani/features/auth/domain/usecases/recuperar_contrasena_usecases.dart';

enum EstadoRecuperacion {
  inicial,
  cargando,
  enlaceSolicitado,
  restablecida,
  error,
}

class RecuperacionContrasenaState extends Equatable {
  const RecuperacionContrasenaState(this.estado, {this.mensaje});

  const RecuperacionContrasenaState.inicial()
    : this(EstadoRecuperacion.inicial);

  final EstadoRecuperacion estado;
  final String? mensaje;

  @override
  List<Object?> get props => [estado, mensaje];
}

/// Recuperación de contraseña (HU-M02-10): pedir el enlace y fijar la
/// contraseña nueva. Los errores llegan como [AuthFailure] con mensaje legible.
class RecuperacionContrasenaCubit extends Cubit<RecuperacionContrasenaState> {
  RecuperacionContrasenaCubit({
    required this.solicitarUseCase,
    required this.restablecerUseCase,
  }) : super(const RecuperacionContrasenaState.inicial());

  final SolicitarRecuperacionUseCase solicitarUseCase;
  final RestablecerContrasenaUseCase restablecerUseCase;

  Future<void> solicitarEnlace({
    required String email,
    required String tenantSlug,
  }) => _ejecutar(
    () => solicitarUseCase(email: email, tenantSlug: tenantSlug),
    EstadoRecuperacion.enlaceSolicitado,
  );

  Future<void> restablecer({
    required String accessToken,
    required String newPassword,
    required String tenantSlug,
  }) => _ejecutar(
    () => restablecerUseCase(
      accessToken: accessToken,
      newPassword: newPassword,
      tenantSlug: tenantSlug,
    ),
    EstadoRecuperacion.restablecida,
  );

  Future<void> _ejecutar(
    Future<void> Function() accion,
    EstadoRecuperacion exito,
  ) async {
    emit(const RecuperacionContrasenaState(EstadoRecuperacion.cargando));
    try {
      await accion();
      emit(RecuperacionContrasenaState(exito));
    } on AuthFailure catch (e) {
      emit(
        RecuperacionContrasenaState(
          EstadoRecuperacion.error,
          mensaje: e.message,
        ),
      );
    } catch (_) {
      emit(
        const RecuperacionContrasenaState(
          EstadoRecuperacion.error,
          mensaje: 'Error inesperado de conexión.',
        ),
      );
    }
  }
}
