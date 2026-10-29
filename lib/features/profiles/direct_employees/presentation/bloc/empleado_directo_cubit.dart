import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/features/profiles/direct_employees/domain/entities/empleado_directo.dart';
import 'package:mani/features/profiles/direct_employees/domain/usecases/registrar_empleado_directo_usecase.dart';

sealed class EmpleadoDirectoState extends Equatable {
  const EmpleadoDirectoState();

  @override
  List<Object?> get props => [];
}

class EmpleadoDirectoInitial extends EmpleadoDirectoState {
  const EmpleadoDirectoInitial();
}

class EmpleadoDirectoLoading extends EmpleadoDirectoState {
  const EmpleadoDirectoLoading();
}

class EmpleadoDirectoRegistrado extends EmpleadoDirectoState {
  const EmpleadoDirectoRegistrado(this.empleado);

  final EmpleadoDirectoCreado empleado;

  @override
  List<Object?> get props => [empleado];
}

class EmpleadoDirectoError extends EmpleadoDirectoState {
  const EmpleadoDirectoError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class EmpleadoDirectoCubit extends Cubit<EmpleadoDirectoState> {
  EmpleadoDirectoCubit({required this.registrarUseCase})
    : super(const EmpleadoDirectoInitial());

  final RegistrarEmpleadoDirectoUseCase registrarUseCase;

  Future<void> registrar({
    required String email,
    required String password,
    required String nombreCompleto,
    required List<String> categoriaIds,
    required String telefono,
    required String tipoDocumento,
    required String numeroDocumento,
    required DocumentoIdentidad documento,
  }) async {
    emit(const EmpleadoDirectoLoading());
    try {
      final creado = await registrarUseCase(
        NuevoEmpleadoDirecto(
          email: email,
          password: password,
          nombreCompleto: nombreCompleto,
          categoriaIds: categoriaIds,
          telefono: telefono,
          tipoDocumento: tipoDocumento,
          numeroDocumento: numeroDocumento,
          documento: documento,
        ),
      );
      emit(EmpleadoDirectoRegistrado(creado));
    } on EmpleadoDirectoFailure catch (e) {
      emit(EmpleadoDirectoError(e.message));
    } catch (_) {
      emit(
        const EmpleadoDirectoError(
          'Error inesperado al registrar el empleado directo.',
        ),
      );
    }
  }
}
