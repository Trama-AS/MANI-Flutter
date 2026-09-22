import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mani/features/auth/domain/entities/auth_failure.dart';
import 'package:mani/features/auth/domain/entities/user_entity.dart';
import 'package:mani/features/auth/domain/usecases/login_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_cliente_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_aliado_usecase.dart';
import 'package:mani/features/auth/domain/usecases/register_empresa_usecase.dart';

part 'auth_state.dart';

/// Cubit de autenticación.
///
/// Coordina los casos de uso de autenticación y emite estados de UI.
/// No importa ningún SDK de infraestructura (Supabase, Firebase, etc.);
/// los errores ya llegan convertidos a [AuthFailure] desde el repositorio.
class AuthCubit extends Cubit<AuthState> {
  AuthCubit({
    required this.loginUseCase,
    required this.registerClienteUseCase,
    required this.registerAliadoUseCase,
    required this.registerEmpresaUseCase,
  }) : super(AuthInitial());

  final LoginUseCase loginUseCase;
  final RegisterClienteUseCase registerClienteUseCase;
  final RegisterAliadoUseCase registerAliadoUseCase;
  final RegisterEmpresaUseCase registerEmpresaUseCase;

  Future<void> login(String email, String password) async {
    emit(AuthLoading());
    try {
      final user = await loginUseCase(email, password);
      emit(AuthAuthenticated(user: user));
    } on AuthFailure catch (e) {
      emit(AuthError(message: e.message));
    } catch (_) {
      emit(const AuthError(message: 'Error inesperado de conexión.'));
    }
  }

  Future<void> registerCliente({
    required String email,
    required String password,
    required String nombreCompleto,
    required String tenantId,
    String? telefono,
    String? direccionHogar,
  }) async {
    emit(AuthLoading());
    try {
      final result = await registerClienteUseCase(
        email: email,
        password: password,
        nombreCompleto: nombreCompleto,
        tenantId: tenantId,
        telefono: telefono,
        direccionHogar: direccionHogar,
      );
      emit(AuthRegistrationSuccess(result: result));
    } on AuthFailure catch (e) {
      emit(AuthError(message: e.message));
    } catch (e) {
      emit(AuthError(message: 'Error en registro: $e'));
    }
  }

  Future<void> registerAliado({
    required String email,
    required String password,
    required String nombreCompleto,
    required String tenantId,
    required String categoriaId,
    required List<Map<String, String>> documentosKYC,
  }) async {
    emit(AuthLoading());
    try {
      final result = await registerAliadoUseCase(
        email: email,
        password: password,
        nombreCompleto: nombreCompleto,
        tenantId: tenantId,
        categoriaId: categoriaId,
        documentosKYC: documentosKYC,
      );
      emit(AuthRegistrationSuccess(result: result));
    } on AuthFailure catch (e) {
      emit(AuthError(message: e.message));
    } catch (e) {
      emit(AuthError(message: 'Error en registro: $e'));
    }
  }

  Future<void> registerEmpresa({
    required String email,
    required String password,
    required String razonSocial,
    required String nit,
    required String tenantId,
    required String nombreRepresentante,
    String? docRepresentante,
    String? telefonoContacto,
    String? categoriaId,
    required List<Map<String, String>> documentosKYC,
  }) async {
    emit(AuthLoading());
    try {
      final result = await registerEmpresaUseCase(
        email: email,
        password: password,
        razonSocial: razonSocial,
        nit: nit,
        tenantId: tenantId,
        nombreRepresentante: nombreRepresentante,
        docRepresentante: docRepresentante,
        telefonoContacto: telefonoContacto,
        categoriaId: categoriaId,
        documentosKYC: documentosKYC,
      );
      emit(AuthRegistrationSuccess(result: result));
    } on AuthFailure catch (e) {
      emit(AuthError(message: e.message));
    } catch (e) {
      emit(AuthError(message: 'Error en registro: $e'));
    }
  }
}
