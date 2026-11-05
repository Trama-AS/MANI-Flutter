import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/features/services/quotes/domain/cotizacion.dart';

import '../data/ejecucion_datasource.dart';

class EjecucionState extends Equatable {
  const EjecucionState({
    this.cargando = false,
    this.enviando = false,
    this.ejecucion,
    this.error,
    this.aviso,
    this.avisoEsError = false,
  });

  final bool cargando;
  final bool enviando;
  final Ejecucion? ejecucion;
  final String? error;
  final String? aviso;
  final bool avisoEsError;

  @override
  List<Object?> get props => [
    cargando,
    enviando,
    ejecucion,
    error,
    aviso,
    avisoEsError,
  ];
}

/// Inicio y fin del servicio (US-04.3.1 / SCRUM-868). Tras cada marca se vuelve
/// a consultar a Core, que pone la hora y es el dueño del estado.
class EjecucionCubit extends Cubit<EjecucionState> {
  EjecucionCubit(this._fuente, this.solicitudId)
    : super(const EjecucionState());

  final FuenteEjecucion _fuente;
  final String solicitudId;

  Future<void> cargar() async {
    emit(EjecucionState(cargando: true, ejecucion: state.ejecucion));
    try {
      final e = await _fuente.consultar(solicitudId);
      if (isClosed) return;
      emit(EjecucionState(ejecucion: e));
    } on CotizacionFailure catch (f) {
      if (isClosed) return;
      emit(EjecucionState(ejecucion: state.ejecucion, error: f.mensajeUsuario));
    }
  }

  Future<void> marcar(HitoEjecucion hito, {String? observacion}) async {
    if (state.enviando) return;
    emit(EjecucionState(enviando: true, ejecucion: state.ejecucion));
    try {
      await _fuente.marcar(solicitudId, hito, observacion: observacion);
    } on CotizacionFailure catch (f) {
      if (isClosed) return;
      emit(
        EjecucionState(
          ejecucion: state.ejecucion,
          aviso: f.mensajeUsuario,
          avisoEsError: true,
        ),
      );
      return;
    }
    if (isClosed) return;
    final texto = hito == HitoEjecucion.inicio
        ? 'Registraste el inicio del servicio.'
        : 'Registraste el fin del servicio.';
    try {
      final e = await _fuente.consultar(solicitudId);
      if (isClosed) return;
      emit(EjecucionState(ejecucion: e, aviso: texto));
    } on CotizacionFailure {
      // La marca ya quedó en Core: no se reporta como fallo.
      if (isClosed) return;
      emit(
        EjecucionState(
          ejecucion: state.ejecucion,
          aviso:
              '$texto No se pudo actualizar la vista; desliza para refrescar.',
        ),
      );
    }
  }
}
