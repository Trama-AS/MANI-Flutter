import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/features/availability/domain/entities/ausencia.dart';
import 'package:mani/features/availability/domain/failures/disponibilidad_failure.dart';
import 'package:mani/features/availability/domain/repositories/i_disponibilidad_repository.dart';

part 'disponibilidad_state.dart';

/// Cubit de la disponibilidad del aliado (US-02.1.6): lista sus ausencias y
/// permite crearlas, editarlas y borrarlas. Tras cada cambio recarga desde
/// el servidor, que es quien decide si el aliado está disponible ahora.
class DisponibilidadCubit extends Cubit<DisponibilidadState> {
  DisponibilidadCubit({required this.repository, DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now,
      super(const DisponibilidadState());

  final IDisponibilidadRepository repository;
  final DateTime Function() _ahora;

  DateTime ahora() => _ahora();

  Future<void> cargar({bool silencioso = false}) async {
    if (!silencioso) {
      emit(state.copyWith(carga: CargaDisponibilidad.cargando, falla: null));
    }
    try {
      final datos = await repository.obtener();
      emit(
        state.copyWith(
          carga: CargaDisponibilidad.listo,
          ausencias: datos.ausencias,
          disponibleAhora: datos.disponibleAhora,
          falla: null,
        ),
      );
    } on DisponibilidadFailure catch (f) {
      if (silencioso && state.carga == CargaDisponibilidad.listo) {
        emit(
          state.copyWith(aviso: AvisoDisponibilidad.error(f.mensajeUsuario)),
        );
      } else {
        emit(state.copyWith(carga: CargaDisponibilidad.error, falla: f));
      }
    }
  }

  /// Devuelve true si se guardó; el formulario se cierra solo en ese caso.
  Future<bool> crear(BorradorAusencia borrador) =>
      _guardar(() => repository.crear(borrador), 'Ausencia registrada');

  Future<bool> editar(String id, BorradorAusencia borrador) =>
      _guardar(() => repository.editar(id, borrador), 'Ausencia actualizada');

  Future<void> eliminar(String id) async {
    await _guardar(
      () => repository.eliminar(id),
      'Ausencia eliminada. Vuelves a recibir solicitudes en ese horario.',
    );
  }

  Future<bool> _guardar(Future<Object?> Function() op, String exito) async {
    if (state.guardando) return false;
    emit(state.copyWith(guardando: true, aviso: null));
    try {
      await op();
      emit(
        state.copyWith(
          guardando: false,
          aviso: AvisoDisponibilidad.exito(exito),
        ),
      );
      await cargar(silencioso: true);
      return true;
    } on DisponibilidadFailure catch (f) {
      emit(
        state.copyWith(
          guardando: false,
          aviso: AvisoDisponibilidad.error(f.mensajeUsuario),
        ),
      );
      // La ausencia pudo borrarse en otra sesión: se refresca la lista.
      if (f.tipo == DisponibilidadErrorTipo.noEncontrada) {
        await cargar(silencioso: true);
      }
      return false;
    }
  }
}
