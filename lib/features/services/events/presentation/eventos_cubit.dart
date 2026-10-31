import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/utils/generador_id.dart';
import 'package:mani/features/services/quotes/domain/cotizacion.dart';
import 'package:mani/features/services/requests/domain/entities/foto_adjunta.dart';

import '../data/cola_eventos.dart';
import '../data/eventos_datasource.dart';

class EventosState extends Equatable {
  const EventosState({
    required this.clave,
    this.cargando = false,
    this.enviando = false,
    this.eventos = const [],
    this.pendientes = const [],
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

  /// Eventos de este servicio que esperan conexión (SCRUM-873).
  final List<EventoPendiente> pendientes;
  final String? error;
  final String? aviso;
  final bool avisoEsError;

  EventosState copiar({
    String? clave,
    bool? cargando,
    bool? enviando,
    List<EventoServicio>? eventos,
    List<EventoPendiente>? pendientes,
    String? error,
    String? aviso,
    bool avisoEsError = false,
  }) => EventosState(
    clave: clave ?? this.clave,
    cargando: cargando ?? this.cargando,
    enviando: enviando ?? this.enviando,
    eventos: eventos ?? this.eventos,
    pendientes: pendientes ?? this.pendientes,
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
    pendientes,
    error,
    aviso,
    avisoEsError,
  ];
}

/// Eventos del servicio (US-04.3.2 / SCRUM-869): el aliado los registra
/// durante la ejecución y ve la secuencia que guarda Core.
///
/// Sin conexión (US-04.3.6 / SCRUM-873), con una [ColaEventos] disponible
/// (solo en el móvil), el evento queda en la cola con su hora de captura y se
/// envía al volver la conexión: al cargar, cada [intervaloReintento] mientras
/// haya pendientes y cuando el aliado lo pide.
class EventosCubit extends Cubit<EventosState> {
  EventosCubit(
    this._fuente,
    this.solicitudId, {
    ColaEventos? cola,
    String? Function()? usuarioActual,
    String Function() generarClave = nuevoUuid,
    DateTime Function() ahora = DateTime.now,
    this.intervaloReintento = const Duration(seconds: 30),
  }) : _cola = cola,
       _usuarioActual = usuarioActual,
       _generarClave = generarClave,
       _ahora = ahora,
       super(EventosState(clave: generarClave()));

  final FuenteEventos _fuente;
  final String solicitudId;
  final ColaEventos? _cola;
  final String? Function()? _usuarioActual;
  final String Function() _generarClave;
  final DateTime Function() _ahora;
  final Duration intervaloReintento;
  Timer? _reintento;

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
    await sincronizar();
  }

  /// Envía la cola. Si algo quedó registrado, refresca la bitácora; si Core
  /// rechazó un evento, avisa el motivo (C2).
  Future<void> sincronizar() async {
    final cola = _cola;
    if (cola == null || !cola.disponible) return;
    final antes = await cola.pendientes();
    final resultado = antes.isEmpty
        ? const ResultadoSincronizacion()
        : await cola.sincronizar(_fuente);
    final pendientes = await cola.pendientes(solicitudId: solicitudId);
    if (isClosed) return;
    _programarReintento(pendientes.isNotEmpty);

    var eventos = state.eventos;
    if (resultado.enviados > 0) {
      try {
        eventos = await _fuente.listar(solicitudId);
      } on CotizacionFailure {
        // Ya quedaron en Core; la lista se refresca en el próximo intento.
      }
      if (isClosed) return;
    }
    final rechazado = resultado.rechazados.firstOrNull;
    final String? aviso;
    if (rechazado != null) {
      aviso =
          'No se pudo enviar el evento «${rechazado.evento.observacion}»: '
          '${rechazado.motivo}';
    } else if (resultado.enviados > 0) {
      aviso = _enviados(resultado.enviados);
    } else {
      aviso = null;
    }
    emit(
      state.copiar(
        eventos: eventos,
        pendientes: pendientes,
        aviso: aviso,
        avisoEsError: rechazado != null,
      ),
    );
  }

  static String _enviados(int n) => n == 1
      ? 'Se envió 1 evento que estaba pendiente.'
      : 'Se enviaron $n eventos que estaban pendientes.';

  void _programarReintento(bool hayPendientes) {
    if (!hayPendientes) {
      _reintento?.cancel();
      _reintento = null;
      return;
    }
    _reintento ??= Timer.periodic(intervaloReintento, (_) => sincronizar());
  }

  @override
  Future<void> close() {
    _reintento?.cancel();
    return super.close();
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
      if (f.tipo == CotizacionErrorTipo.sinConexion) {
        return _encolar(tipo: tipo, observacion: observacion, foto: foto, f: f);
      }
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

  /// C1 de la 873: sin conexión el evento queda en la cola con la hora en que
  /// el aliado lo tomó y la misma clave del intento, así no se duplica si ese
  /// intento sí había llegado a Core.
  Future<bool> _encolar({
    required TipoEventoAliado tipo,
    required String observacion,
    required FotoAdjunta? foto,
    required CotizacionFailure f,
  }) async {
    final cola = _cola;
    final usuario = _usuarioActual?.call();
    if (cola == null || !cola.disponible || usuario == null) {
      return _noRegistrado(f.mensajeUsuario);
    }
    try {
      await cola.encolar(
        EventoPendiente(
          clave: state.clave,
          usuarioId: usuario,
          solicitudId: solicitudId,
          tipo: tipo,
          observacion: observacion,
          ocurridoEn: _ahora().toUtc(),
          foto: foto,
        ),
      );
    } on ColaLlena catch (lleno) {
      return _noRegistrado(lleno.mensajeUsuario);
    }
    final pendientes = await cola.pendientes(solicitudId: solicitudId);
    if (isClosed) return true;
    _programarReintento(true);
    emit(
      state.copiar(
        clave: _generarClave(),
        enviando: false,
        pendientes: pendientes,
        aviso:
            'Sin conexión: el evento quedó guardado y se enviará al recuperar '
            'la señal.',
      ),
    );
    return true;
  }

  bool _noRegistrado(String mensaje) {
    if (!isClosed) {
      emit(state.copiar(enviando: false, aviso: mensaje, avisoEsError: true));
    }
    return false;
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
