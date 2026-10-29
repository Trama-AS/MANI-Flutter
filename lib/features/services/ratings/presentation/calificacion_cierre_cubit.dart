import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/calificacion_cierre_datasource.dart';
import '../domain/calificacion_cierre_modelos.dart';

class CalificacionCierreState extends Equatable {
  const CalificacionCierreState({
    this.cargando = false,
    this.enviando = false,
    this.resumen,
    this.error,
    this.mensajeExito,
  });

  final bool cargando;
  final bool enviando;
  final ResumenCalificacionesSolicitud? resumen;
  final String? error;
  final String? mensajeExito;

  @override
  List<Object?> get props => [
    cargando,
    enviando,
    resumen,
    error,
    mensajeExito,
  ];
}

/// Estado de calificación bidireccional y cierre condicionado (SCRUM-874,
/// SCRUM-875 y SCRUM-1418).
class CalificacionCierreCubit extends Cubit<CalificacionCierreState> {
  CalificacionCierreCubit(this._fuente, {required this.solicitudId})
    : super(const CalificacionCierreState());

  final FuenteModuloM08 _fuente;
  final String solicitudId;

  Future<void> cargar() async {
    emit(CalificacionCierreState(cargando: true, resumen: state.resumen));
    try {
      final resumen = await _fuente.obtenerCalificaciones(solicitudId);
      if (isClosed) return;
      emit(CalificacionCierreState(resumen: resumen));
    } on ModuloM08Failure catch (f) {
      if (isClosed) return;
      emit(
        CalificacionCierreState(
          resumen: state.resumen,
          error: f.mensajeUsuario,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(
        CalificacionCierreState(
          resumen: state.resumen,
          error: const ModuloM08Failure(
            ModuloM08ErrorTipo.desconocido,
          ).mensajeUsuario,
        ),
      );
    }
  }

  Future<bool> calificar({required int puntaje, String? comentario}) async {
    if (puntaje < 1 || puntaje > 5) {
      emit(
        CalificacionCierreState(
          resumen: state.resumen,
          error: const ModuloM08Failure(
            ModuloM08ErrorTipo.puntajeInvalido,
          ).mensajeUsuario,
        ),
      );
      return false;
    }
    if (comentario != null && comentario.trim().length > 500) {
      emit(
        CalificacionCierreState(
          resumen: state.resumen,
          error: const ModuloM08Failure(
            ModuloM08ErrorTipo.comentarioInvalido,
          ).mensajeUsuario,
        ),
      );
      return false;
    }

    emit(CalificacionCierreState(enviando: true, resumen: state.resumen));
    try {
      await _fuente.registrarCalificacion(
        solicitudId: solicitudId,
        puntaje: puntaje,
        comentario: comentario,
      );
      final actualizado = await _fuente.obtenerCalificaciones(solicitudId);
      if (isClosed) return true;
      emit(
        CalificacionCierreState(
          resumen: actualizado,
          mensajeExito: actualizado.cierre.cierreCompleto
              ? 'Calificación registrada. El servicio quedó cerrado.'
              : 'Calificación registrada. Pendiente la calificación de la otra parte para el cierre definitivo.',
        ),
      );
      return true;
    } on ModuloM08Failure catch (f) {
      if (isClosed) return false;
      emit(
        CalificacionCierreState(
          resumen: state.resumen,
          error: f.mensajeUsuario,
        ),
      );
      return false;
    } catch (_) {
      if (isClosed) return false;
      emit(
        CalificacionCierreState(
          resumen: state.resumen,
          error: const ModuloM08Failure(
            ModuloM08ErrorTipo.desconocido,
          ).mensajeUsuario,
        ),
      );
      return false;
    }
  }

  Future<bool> cerrarSolicitud() async {
    emit(CalificacionCierreState(enviando: true, resumen: state.resumen));
    try {
      await _fuente.cerrarSolicitud(solicitudId);
      final actualizado = await _fuente.obtenerCalificaciones(solicitudId);
      if (isClosed) return true;
      emit(
        CalificacionCierreState(
          resumen: actualizado,
          mensajeExito: 'Solicitud cerrada definitivamente.',
        ),
      );
      return true;
    } on ModuloM08Failure catch (f) {
      if (isClosed) return false;
      emit(
        CalificacionCierreState(
          resumen: state.resumen,
          error: f.mensajeUsuario,
        ),
      );
      return false;
    }
  }
}

class HistorialServiciosState extends Equatable {
  const HistorialServiciosState({
    this.cargando = false,
    this.registros = const [],
    this.error,
  });

  final bool cargando;
  final List<RegistroHistorialServicio> registros;
  final String? error;

  @override
  List<Object?> get props => [cargando, registros, error];
}

/// Estado del historial de servicios del cliente (SCRUM-879) o de trabajos del
/// aliado (SCRUM-880).
class HistorialServiciosCubit extends Cubit<HistorialServiciosState> {
  HistorialServiciosCubit(this._fuente, {required this.esAliado})
    : super(const HistorialServiciosState());

  final FuenteModuloM08 _fuente;
  final bool esAliado;

  Future<void> cargar() async {
    emit(
      HistorialServiciosState(
        cargando: true,
        registros: state.registros,
      ),
    );
    try {
      final registros = esAliado
          ? await _fuente.listarHistorialAliado()
          : await _fuente.listarHistorialCliente();
      if (isClosed) return;
      emit(HistorialServiciosState(registros: registros));
    } on ModuloM08Failure catch (f) {
      if (isClosed) return;
      emit(
        HistorialServiciosState(
          registros: state.registros,
          error: f.mensajeUsuario,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(
        HistorialServiciosState(
          registros: state.registros,
          error: const ModuloM08Failure(
            ModuloM08ErrorTipo.desconocido,
          ).mensajeUsuario,
        ),
      );
    }
  }
}

