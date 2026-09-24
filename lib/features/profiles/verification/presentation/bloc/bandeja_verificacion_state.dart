part of 'bandeja_verificacion_cubit.dart';

enum EstadoCarga { inicial, cargando, listo, error }

/// Mensaje de un solo uso para SnackBar. El [id] cambia en cada aviso para que
/// dos mensajes iguales seguidos también se muestren.
class AvisoVerificacion extends Equatable {
  const AvisoVerificacion(this.id, this.mensaje, {this.esError = false});

  final int id;
  final String mensaje;
  final bool esError;

  @override
  List<Object?> get props => [id, mensaje, esError];
}

const Object _sinCambio = Object();

class BandejaVerificacionState extends Equatable {
  const BandejaVerificacionState({
    this.carga = EstadoCarga.inicial,
    this.solicitudes = const [],
    this.filtro = EstadoVerificacion.pendiente,
    this.busqueda = '',
    this.seleccionadaId,
    this.cargandoDetalleId,
    this.procesandoId,
    this.error,
    this.aviso,
  });

  final EstadoCarga carga;
  final List<SolicitudAliado> solicitudes;
  final EstadoVerificacion filtro;
  final String busqueda;
  final String? seleccionadaId;
  final String? cargandoDetalleId;

  /// Aliado cuya decisión se está enviando; bloquea otras decisiones.
  final String? procesandoId;
  final VerificacionFailure? error;
  final AvisoVerificacion? aviso;

  List<SolicitudAliado> get visibles => solicitudes
      .where((s) => s.estado == filtro && s.coincideCon(busqueda))
      .toList(growable: false);

  int conteo(EstadoVerificacion estado) =>
      solicitudes.where((s) => s.estado == estado).length;

  SolicitudAliado? porId(String? id) {
    if (id == null) return null;
    for (final s in solicitudes) {
      if (s.id == id) return s;
    }
    return null;
  }

  SolicitudAliado? get seleccionada => porId(seleccionadaId);

  bool get procesando => procesandoId != null;

  BandejaVerificacionState copyWith({
    EstadoCarga? carga,
    List<SolicitudAliado>? solicitudes,
    EstadoVerificacion? filtro,
    String? busqueda,
    Object? seleccionadaId = _sinCambio,
    Object? cargandoDetalleId = _sinCambio,
    Object? procesandoId = _sinCambio,
    Object? error = _sinCambio,
    Object? aviso = _sinCambio,
  }) => BandejaVerificacionState(
    carga: carga ?? this.carga,
    solicitudes: solicitudes ?? this.solicitudes,
    filtro: filtro ?? this.filtro,
    busqueda: busqueda ?? this.busqueda,
    seleccionadaId: identical(seleccionadaId, _sinCambio)
        ? this.seleccionadaId
        : seleccionadaId as String?,
    cargandoDetalleId: identical(cargandoDetalleId, _sinCambio)
        ? this.cargandoDetalleId
        : cargandoDetalleId as String?,
    procesandoId: identical(procesandoId, _sinCambio)
        ? this.procesandoId
        : procesandoId as String?,
    error: identical(error, _sinCambio)
        ? this.error
        : error as VerificacionFailure?,
    aviso: identical(aviso, _sinCambio)
        ? this.aviso
        : aviso as AvisoVerificacion?,
  );

  @override
  List<Object?> get props => [
    carga,
    solicitudes,
    filtro,
    busqueda,
    seleccionadaId,
    cargandoDetalleId,
    procesandoId,
    error?.tipo,
    aviso,
  ];
}
