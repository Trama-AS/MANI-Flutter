import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/features/profiles/site_rules/domain/entities/reglas_sitio.dart';
import 'package:mani/features/profiles/site_rules/domain/usecases/reglas_sitio_usecases.dart';

class ReglasSitioState extends Equatable {
  const ReglasSitioState({
    this.reglas,
    this.cargando = false,
    this.guardadoExitoso = false,
    this.error,
  });

  final ReglasContextualesSitio? reglas;
  final bool cargando;
  final bool guardadoExitoso;
  final String? error;

  @override
  List<Object?> get props => [reglas, cargando, guardadoExitoso, error];
}

class ReglasSitioCubit extends Cubit<ReglasSitioState> {
  ReglasSitioCubit({
    required this.obtenerUseCase,
    required this.configurarUseCase,
  }) : super(const ReglasSitioState());

  final ObtenerReglasSitioUseCase obtenerUseCase;
  final ConfigurarReglasSitioUseCase configurarUseCase;

  Future<void> cargarReglas(String siteId) async {
    emit(ReglasSitioState(reglas: state.reglas, cargando: true));
    try {
      final reglas = await obtenerUseCase(siteId);
      emit(ReglasSitioState(reglas: reglas));
    } on ReglasSitioFailure catch (e) {
      emit(ReglasSitioState(reglas: state.reglas, error: e.message));
    } catch (_) {
      emit(
        ReglasSitioState(
          reglas: state.reglas,
          error: 'Error al cargar las reglas del sitio.',
        ),
      );
    }
  }

  Future<void> guardarReglas(ReglasContextualesSitio nuevasReglas) async {
    emit(ReglasSitioState(reglas: state.reglas, cargando: true));
    try {
      final actualizadas = await configurarUseCase(nuevasReglas);
      emit(ReglasSitioState(reglas: actualizadas, guardadoExitoso: true));
    } on ReglasSitioFailure catch (e) {
      emit(ReglasSitioState(reglas: state.reglas, error: e.message));
    } catch (_) {
      emit(
        ReglasSitioState(
          reglas: state.reglas,
          error: 'Error al guardar las reglas del sitio.',
        ),
      );
    }
  }
}
