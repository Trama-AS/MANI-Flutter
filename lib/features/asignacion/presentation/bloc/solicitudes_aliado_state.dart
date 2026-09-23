part of 'solicitudes_aliado_cubit.dart';

enum CargaSolicitudes { inicial, cargando, listo, error }

enum PestanaSolicitudes { disponibles, misTrabajos }

/// Qué se está enviando para la solicitud en [SolicitudesAliadoState.procesandoId].
enum AccionSolicitud { aceptando, rechazando }

enum TipoAviso { exito, info, error }

/// Mensaje de un solo uso para SnackBar. El [id] cambia en cada aviso para que
/// dos mensajes iguales seguidos también se muestren.
class AvisoSolicitudes extends Equatable {
  const AvisoSolicitudes(this.id, this.mensaje, this.tipo);

  final int id;
  final String mensaje;
  final TipoAviso tipo;

  @override
  List<Object?> get props => [id, mensaje, tipo];
}

const Object _sinCambio = Object();

class SolicitudesAliadoState extends Equatable {
  const SolicitudesAliadoState({
    this.carga = CargaSolicitudes.inicial,
    this.bandeja = const BandejaSolicitudes(),
    this.pestana = PestanaSolicitudes.disponibles,
    this.procesandoId,
    this.accion,
    this.recienAsignadaId,
    this.error,
    this.aviso,
  });

  final CargaSolicitudes carga;
  final BandejaSolicitudes bandeja;
  final PestanaSolicitudes pestana;

  /// Solicitud cuya acción se está enviando; bloquea otras acciones.
  final String? procesandoId;
  final AccionSolicitud? accion;

  /// Recién ganada: se resalta en "Mis trabajos".
  final String? recienAsignadaId;
  final AsignacionFailure? error;
  final AvisoSolicitudes? aviso;

  List<SolicitudEntity> get visibles => switch (pestana) {
    PestanaSolicitudes.disponibles => bandeja.disponibles,
    PestanaSolicitudes.misTrabajos => bandeja.misTrabajos,
  };

  bool get procesando => procesandoId != null;

  SolicitudesAliadoState copyWith({
    CargaSolicitudes? carga,
    BandejaSolicitudes? bandeja,
    PestanaSolicitudes? pestana,
    Object? procesandoId = _sinCambio,
    Object? accion = _sinCambio,
    Object? recienAsignadaId = _sinCambio,
    Object? error = _sinCambio,
    Object? aviso = _sinCambio,
  }) => SolicitudesAliadoState(
    carga: carga ?? this.carga,
    bandeja: bandeja ?? this.bandeja,
    pestana: pestana ?? this.pestana,
    procesandoId: identical(procesandoId, _sinCambio)
        ? this.procesandoId
        : procesandoId as String?,
    accion: identical(accion, _sinCambio)
        ? this.accion
        : accion as AccionSolicitud?,
    recienAsignadaId: identical(recienAsignadaId, _sinCambio)
        ? this.recienAsignadaId
        : recienAsignadaId as String?,
    error: identical(error, _sinCambio)
        ? this.error
        : error as AsignacionFailure?,
    aviso: identical(aviso, _sinCambio)
        ? this.aviso
        : aviso as AvisoSolicitudes?,
  );

  @override
  List<Object?> get props => [
    carga,
    bandeja,
    pestana,
    procesandoId,
    accion,
    recienAsignadaId,
    error?.tipo,
    aviso,
  ];
}
