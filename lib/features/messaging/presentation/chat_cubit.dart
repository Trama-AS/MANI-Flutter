import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/utils/generador_id.dart';

import '../data/mensajes_datasource.dart';
import '../domain/mensaje.dart';

class ChatState extends Equatable {
  const ChatState({
    this.mensajes = const [],
    this.cargando = true,
    this.enviando = false,
    this.soloLectura = false,
    this.errorEnvio,
    this.errorLectura,
  });

  final List<Mensaje> mensajes;

  /// Primera carga del hilo en curso.
  final bool cargando;
  final bool enviando;

  /// El servicio ya no admite mensajes nuevos: se lee, no se escribe.
  final bool soloLectura;
  final MensajeFailure? errorEnvio;

  /// Falla de la última consulta. Si es [MensajeFailure.definitivo] se dejó de
  /// consultar; si no, se reintenta en el siguiente ciclo.
  final MensajeFailure? errorLectura;

  bool get hiloInaccesible => errorLectura?.definitivo ?? false;
  bool get puedeEscribir => !soloLectura && !hiloInaccesible;

  ChatState copiar({
    List<Mensaje>? mensajes,
    bool? cargando,
    bool? enviando,
    bool? soloLectura,
    MensajeFailure? errorEnvio,
    bool limpiarErrorEnvio = false,
    MensajeFailure? errorLectura,
    bool limpiarErrorLectura = false,
  }) => ChatState(
    mensajes: mensajes ?? this.mensajes,
    cargando: cargando ?? this.cargando,
    enviando: enviando ?? this.enviando,
    soloLectura: soloLectura ?? this.soloLectura,
    errorEnvio: limpiarErrorEnvio ? null : (errorEnvio ?? this.errorEnvio),
    errorLectura: limpiarErrorLectura
        ? null
        : (errorLectura ?? this.errorLectura),
  );

  @override
  List<Object?> get props => [
    mensajes,
    cargando,
    enviando,
    soloLectura,
    errorEnvio,
    errorLectura,
  ];
}

/// Chat cliente-aliado de un servicio (SCRUM-881, HU-M09-02).
///
/// No hay tiempo real: mientras la pantalla está abierta se consulta a Core cada
/// [intervalo] pidiendo solo lo posterior al último mensaje conocido. Dos
/// detalles evitan perder o duplicar mensajes:
///
/// * El cursor avanza solo con lo que devuelve la consulta, nunca con lo que
///   uno mismo envía; si no, un mensaje del otro anterior al mío se saltaría.
/// * Un mensaje enviado no se agrega a mano: tras guardarse se consulta de
///   inmediato y llega en el orden de Core. La misma clave de idempotencia se
///   conserva mientras el texto no cambie, así reintentar tras un fallo de red
///   no lo duplica aunque Core ya lo hubiera guardado.
class ChatCubit extends Cubit<ChatState> {
  ChatCubit(
    this._fuente,
    this.solicitudId, {
    this.intervalo = const Duration(seconds: 5),
    String Function() generarClave = nuevoUuid,
  }) : _generarClave = generarClave,
       super(const ChatState());

  final FuenteMensajes _fuente;
  final String solicitudId;
  final Duration intervalo;
  final String Function() _generarClave;

  Timer? _timer;
  bool _consultando = false;
  bool _repetir = false;
  bool _pausado = false;
  String? _cursor;

  String? _textoPendiente;
  String? _clavePendiente;

  /// Primera carga y arranque de la consulta periódica.
  Future<void> iniciar() async {
    await _consultar();
    _programar();
  }

  /// Con la app en segundo plano no se consulta.
  void pausar() {
    _pausado = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> reanudar() async {
    if (!_pausado) return;
    _pausado = false;
    await _consultar();
    _programar();
  }

  void _programar() {
    _timer?.cancel();
    _timer = null;
    if (isClosed || _pausado || state.hiloInaccesible) return;
    _timer = Timer.periodic(intervalo, (_) => _consultar());
  }

  Future<void> _consultar() async {
    if (isClosed) return;
    if (_consultando) {
      _repetir = true;
      return;
    }
    _consultando = true;
    try {
      do {
        _repetir = false;
        await _consultarUnaVez();
      } while (_repetir && !isClosed);
    } finally {
      _consultando = false;
    }
  }

  Future<void> _consultarUnaVez() async {
    try {
      final nuevos = await _fuente.listar(solicitudId, despuesDe: _cursor);
      if (isClosed) return;
      if (nuevos.isNotEmpty) _cursor = nuevos.last.id;
      final conocidos = {for (final m in state.mensajes) m.id};
      final agregados = [
        for (final m in nuevos)
          if (!conocidos.contains(m.id)) m,
      ];
      emit(
        state.copiar(
          mensajes: agregados.isEmpty
              ? null
              : [...state.mensajes, ...agregados],
          cargando: false,
          limpiarErrorLectura: true,
        ),
      );
    } on MensajeFailure catch (f) {
      if (isClosed) return;
      emit(state.copiar(cargando: false, errorLectura: f));
      if (f.definitivo) {
        _timer?.cancel();
        _timer = null;
      }
    }
  }

  /// Envía [texto]. Devuelve `true` si Core lo guardó (la pantalla limpia el
  /// campo); si falla, el texto queda para reintentar.
  Future<bool> enviar(String texto) async {
    final contenido = texto.trim();
    if (contenido.isEmpty || state.enviando || !state.puedeEscribir) {
      return false;
    }
    if (contenido.length > maxCaracteresMensaje) {
      emit(
        state.copiar(
          errorEnvio: MensajeFailure(
            MensajeErrorTipo.datosInvalidos,
            detalle:
                'El mensaje no puede pasar de $maxCaracteresMensaje '
                'caracteres.',
          ),
        ),
      );
      return false;
    }
    if (_textoPendiente != contenido) {
      _textoPendiente = contenido;
      _clavePendiente = _generarClave();
    }
    emit(state.copiar(enviando: true, limpiarErrorEnvio: true));
    try {
      await _fuente.enviar(
        solicitudId,
        contenido,
        claveIdempotencia: _clavePendiente!,
      );
      _textoPendiente = null;
      _clavePendiente = null;
      if (isClosed) return true;
      emit(state.copiar(enviando: false));
      await _consultar();
      return true;
    } on MensajeFailure catch (f) {
      if (isClosed) return false;
      emit(
        state.copiar(
          enviando: false,
          errorEnvio: f,
          soloLectura: f.tipo == MensajeErrorTipo.servicioCerrado,
        ),
      );
      return false;
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
