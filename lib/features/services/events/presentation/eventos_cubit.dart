import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/utils/generador_id.dart';
import 'package:mani/features/services/quotes/domain/cotizacion.dart';
import 'package:mani/features/services/requests/domain/entities/foto_adjunta.dart';

import '../data/eventos_datasource.dart';

class EventosState extends Equatable {
  const EventosState({
    required this.clave,
    this.cargando = false,
    this.enviando = false,
    this.eventos = const [],
    this.error,
    this.aviso,
    this.avisoEsError = false,
  });

  /// Clave del envío en curso: se conserva si falla, para que reintentar no
  /// duplique, y se renueva cuando el evento queda registrado.
  final String clave;
  final bool cargando;
  final bool enviando;
  final List<EventoServicio> eventos;
  final String? error;
  final String? aviso;
  final bool avisoEsError;

  EventosState copiar({
    String? clave,
    bool? cargando,
    bool? enviando,
    List<EventoServicio>? eventos,
    String? error,
    String? aviso,
    bool avisoEsError = false,
  }) => EventosState(
    clave: clave ?? this.clave,
    cargando: cargando ?? this.cargando,
    enviando: enviando ?? this.enviando,
    eventos: eventos ?? this.eventos,
    error: error,
    aviso: aviso,
    avisoEsError: avisoEsError,
  );

  @override
  List<Object?> get props => [
    clave,
    cargando,
    enviando,
    eventos,
    error,
    aviso,
    avisoEsError,
  ];
}

/// Eventos del servicio (US-04.3.2 / SCRUM-869): el aliado los registra
/// durante la ejecución y ve la secuencia que guarda Core.
class EventosCubit extends Cubit<EventosState> {
  EventosCubit(
    this._fuente,
    this.solicitudId, {
    String Function() generarClave = nuevoUuid,
  }) : _generarClave = generarClave,
       super(EventosState(clave: generarClave()));

  final FuenteEventos _fuente;
  final String solicitudId;
  final String Function() _generarClave;

  Future<void> cargar() async {
    emit(state.copiar(cargando: true));
    try {
      final lista = await _fuente.listar(solicitudId);
      if (isClosed) return;
      emit(state.copiar(cargando: false, eventos: lista));
    } on CotizacionFailure catch (f) {
      if (isClosed) return;
      emit(state.copiar(cargando: false, error: f.mensajeUsuario));
    }
  }

  /// Devuelve `true` si el evento quedó registrado, para limpiar el formulario.
  Future<bool> registrar({
    required TipoEventoAliado tipo,
    required String observacion,
    FotoAdjunta? foto,
  }) async {
    if (state.enviando) return false;
    emit(state.copiar(enviando: true));
    try {
      await _fuente.registrar(
        solicitudId,
        tipo: tipo,
        observacion: observacion,
        claveIdempotencia: state.clave,
        foto: foto,
      );
    } on CotizacionFailure catch (f) {
      if (isClosed) return false;
      emit(
        state.copiar(
          enviando: false,
          aviso: f.mensajeUsuario,
          avisoEsError: true,
        ),
      );
      return false;
    }
    if (isClosed) return true;
    final nueva = _generarClave();
    try {
      final lista = await _fuente.listar(solicitudId);
      if (isClosed) return true;
      emit(
        state.copiar(
          clave: nueva,
          enviando: false,
          eventos: lista,
          aviso: 'Evento registrado.',
        ),
      );
    } on CotizacionFailure {
      // El evento ya quedó en Core: no se reporta como fallo.
      if (isClosed) return true;
      emit(
        state.copiar(
          clave: nueva,
          enviando: false,
          aviso:
              'Evento registrado. No se pudo actualizar la lista; desliza para refrescar.',
        ),
      );
    }
    return true;
  }

  /// URL de la foto del evento (SCRUM-870), o `null` si no se pudo obtener; en
  /// ese caso se avisa el motivo sin cambiar la bitácora.
  Future<Uri?> urlEvidencia(String eventoId) async {
    try {
      return await _fuente.urlEvidencia(solicitudId, eventoId);
    } on CotizacionFailure catch (f) {
      if (isClosed) return null;
      emit(state.copiar(aviso: f.mensajeUsuario, avisoEsError: true));
      return null;
    }
  }
}
