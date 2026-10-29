import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:mani/features/services/quotes/domain/cotizacion.dart';
import 'package:mani/features/services/requests/domain/entities/foto_adjunta.dart';

import 'eventos_datasource.dart';

/// Evento que el aliado registró sin conexión (US-04.3.6 / SCRUM-873). Guarda
/// solo lo necesario para enviarlo (decisión del PO): servicio, tipo,
/// observación, foto y hora de captura, que Core toma como la oficial.
class EventoPendiente extends Equatable {
  const EventoPendiente({
    required this.clave,
    required this.usuarioId,
    required this.solicitudId,
    required this.tipo,
    required this.observacion,
    required this.ocurridoEn,
    this.foto,
  });

  /// Clave de idempotencia: la misma en cada reintento, así Core no duplica.
  final String clave;
  final String usuarioId;
  final String solicitudId;
  final TipoEventoAliado tipo;
  final String observacion;
  final DateTime ocurridoEn;
  final FotoAdjunta? foto;

  int get bytes => (foto?.bytes.length ?? 0) + observacion.length;

  @override
  List<Object?> get props => [
    clave,
    usuarioId,
    solicitudId,
    tipo,
    observacion,
    ocurridoEn,
    foto,
  ];
}

/// Dónde vive la cola. En el móvil son archivos privados de la app; en la web
/// no hay modo sin conexión (decisión del PO) y [disponible] es `false`.
abstract interface class AlmacenColaEventos {
  bool get disponible;

  /// En el orden en que se registraron.
  Future<List<EventoPendiente>> leer();

  Future<void> agregar(EventoPendiente evento);

  Future<void> quitar(String clave);

  Future<void> vaciar();
}

/// Almacén sin persistencia: para la web (no disponible) y las pruebas.
class AlmacenColaEnMemoria implements AlmacenColaEventos {
  AlmacenColaEnMemoria({this.disponible = true});

  @override
  final bool disponible;
  final _eventos = <EventoPendiente>[];

  @override
  Future<List<EventoPendiente>> leer() async => List.unmodifiable(_eventos);

  @override
  Future<void> agregar(EventoPendiente evento) async => _eventos.add(evento);

  @override
  Future<void> quitar(String clave) async =>
      _eventos.removeWhere((e) => e.clave == clave);

  @override
  Future<void> vaciar() async => _eventos.clear();
}

/// La cola alcanzó el límite del PO: 20 eventos o 50 MB.
class ColaLlena implements Exception {
  const ColaLlena();

  String get mensajeUsuario =>
      'Tienes ${ColaEventos.maxEventos} eventos o '
      '${ColaEventos.maxBytes ~/ (1024 * 1024)} MB pendientes de enviar. '
      'Conéctate para enviarlos antes de registrar más.';
}

/// Evento que Core rechazó de forma definitiva al sincronizar: sale de la cola
/// y el aliado ve el motivo.
class EventoRechazado extends Equatable {
  const EventoRechazado(this.evento, this.motivo);

  final EventoPendiente evento;
  final String motivo;

  @override
  List<Object?> get props => [evento, motivo];
}

class ResultadoSincronizacion extends Equatable {
  const ResultadoSincronizacion({
    this.enviados = 0,
    this.rechazados = const [],
  });

  final int enviados;
  final List<EventoRechazado> rechazados;

  @override
  List<Object?> get props => [enviados, rechazados];
}

/// Cola de eventos sin conexión (US-04.3.6 / SCRUM-873).
///
/// - C1: se envía en orden, cada evento con su clave y su hora de captura;
///   Core no duplica aunque llegue dos veces.
/// - C2: un fallo de red, 5xx o de sesión deja el evento en la cola y corta la
///   ronda (se reintenta después); un rechazo de Core (400, 403, 404, 409) lo
///   saca de la cola y se informa. Nunca se marca enviado sin respuesta de
///   Core.
/// - C3: es de un usuario: solo se envía con su sesión y se borra al cerrarla.
class ColaEventos {
  ColaEventos(this._almacen, {required String? Function() usuarioActual})
    : _usuarioActual = usuarioActual;

  static const maxEventos = 20;
  static const maxBytes = 50 * 1024 * 1024;

  final AlmacenColaEventos _almacen;
  final String? Function() _usuarioActual;
  Future<ResultadoSincronizacion>? _enCurso;

  bool get disponible => _almacen.disponible;

  /// Pendientes del usuario de la sesión; si se filtra uno de otro usuario
  /// (sesión vencida sin cierre), no se muestra ni se envía.
  Future<List<EventoPendiente>> pendientes({String? solicitudId}) async {
    final usuario = _usuarioActual();
    if (usuario == null || !disponible) return const [];
    final todos = await _almacen.leer();
    return [
      for (final e in todos)
        if (e.usuarioId == usuario &&
            (solicitudId == null || e.solicitudId == solicitudId))
          e,
    ];
  }

  /// Lanza [ColaLlena] si con este evento se pasa del límite.
  Future<void> encolar(EventoPendiente evento) async {
    final todos = await _almacen.leer();
    final bytes = todos.fold<int>(0, (s, e) => s + e.bytes) + evento.bytes;
    if (todos.length >= maxEventos || bytes > maxBytes) throw const ColaLlena();
    await _almacen.agregar(evento);
  }

  Future<void> vaciar() => _almacen.vaciar();

  /// Una sola ronda a la vez: si ya hay una en curso se espera esa.
  Future<ResultadoSincronizacion> sincronizar(FuenteEventos fuente) =>
      _enCurso ??= _sincronizar(fuente).whenComplete(() => _enCurso = null);

  Future<ResultadoSincronizacion> _sincronizar(FuenteEventos fuente) async {
    var enviados = 0;
    final rechazados = <EventoRechazado>[];
    for (final e in await pendientes()) {
      try {
        await fuente.registrar(
          e.solicitudId,
          tipo: e.tipo,
          observacion: e.observacion,
          claveIdempotencia: e.clave,
          foto: e.foto,
          ocurridoEn: e.ocurridoEn,
        );
        enviados++;
      } on CotizacionFailure catch (f) {
        if (_esPasajero(f.tipo)) break;
        rechazados.add(EventoRechazado(e, f.mensajeUsuario));
      }
      await _almacen.quitar(e.clave);
    }
    return ResultadoSincronizacion(enviados: enviados, rechazados: rechazados);
  }

  static bool _esPasajero(CotizacionErrorTipo tipo) => switch (tipo) {
    CotizacionErrorTipo.sinConexion ||
    CotizacionErrorTipo.servicioNoDisponible ||
    CotizacionErrorTipo.sinSesion ||
    CotizacionErrorTipo.desconocido => true,
    CotizacionErrorTipo.sinPermiso ||
    CotizacionErrorTipo.noEncontrada ||
    CotizacionErrorTipo.datosInvalidos ||
    CotizacionErrorTipo.conflicto => false,
  };
}
