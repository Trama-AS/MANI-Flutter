import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/features/profiles/company_sites/domain/entities/sede_empresa.dart';
import 'package:mani/features/profiles/company_sites/domain/usecases/sedes_empresa_usecases.dart';

class SedesEmpresaState extends Equatable {
  const SedesEmpresaState({
    this.sedes = const [],
    this.cargando = false,
    this.error,
  });

  final List<SedeEmpresa> sedes;
  final bool cargando;
  final String? error;

  SedesEmpresaState copyWith({
    List<SedeEmpresa>? sedes,
    bool? cargando,
    String? error,
  }) {
    return SedesEmpresaState(
      sedes: sedes ?? this.sedes,
      cargando: cargando ?? this.cargando,
      error: error,
    );
  }

  @override
  List<Object?> get props => [sedes, cargando, error];
}

class SedesEmpresaCubit extends Cubit<SedesEmpresaState> {
  SedesEmpresaCubit({required this.listarUseCase, required this.agregarUseCase})
    : super(const SedesEmpresaState());

  final ListarSedesEmpresaUseCase listarUseCase;
  final AgregarSedeEmpresaUseCase agregarUseCase;

  Future<void> cargarSedes(String clienteId) async {
    emit(state.copyWith(cargando: true));
    try {
      final lista = await listarUseCase(clienteId);
      emit(SedesEmpresaState(sedes: lista));
    } on SedeEmpresaFailure catch (e) {
      emit(state.copyWith(cargando: false, error: e.message));
    } catch (_) {
      emit(
        state.copyWith(
          cargando: false,
          error: 'No se pudieron cargar las sedes.',
        ),
      );
    }
  }

  Future<void> agregarNuevaSede({
    required String clienteId,
    required String nombre,
    required String direccion,
    required String zonaId,
    String? contactoNombre,
    String? contactoTelefono,
  }) async {
    emit(state.copyWith(cargando: true));
    try {
      final creada = await agregarUseCase(
        clienteId,
        NuevaSedeEmpresa(
          nombre: nombre,
          direccion: direccion,
          zonaId: zonaId,
          contactoNombre: contactoNombre,
          contactoTelefono: contactoTelefono,
        ),
      );
      emit(SedesEmpresaState(sedes: [...state.sedes, creada]));
    } on SedeEmpresaFailure catch (e) {
      emit(state.copyWith(cargando: false, error: e.message));
    } catch (_) {
      emit(
        state.copyWith(cargando: false, error: 'No se pudo agregar la sede.'),
      );
    }
  }
}
