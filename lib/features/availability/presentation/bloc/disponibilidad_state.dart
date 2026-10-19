part of 'disponibilidad_cubit.dart';

enum CargaDisponibilidad { inicial, cargando, listo, error }

/// Mensaje de una sola vez para la SnackBar (éxito o error de una acción).
class AvisoDisponibilidad extends Equatable {
  const AvisoDisponibilidad._(this.mensaje, this.esError, this.marca);

  factory AvisoDisponibilidad.exito(String mensaje) => AvisoDisponibilidad._(
    mensaje,
    false,
    DateTime.now().microsecondsSinceEpoch,
  );

  factory AvisoDisponibilidad.error(String mensaje) => AvisoDisponibilidad._(
    mensaje,
    true,
    DateTime.now().microsecondsSinceEpoch,
  );

  final String mensaje;
  final bool esError;

  /// Distingue dos avisos con el mismo texto, para que ambos se muestren.
  final int marca;

  @override
  List<Object?> get props => [mensaje, esError, marca];
}

class DisponibilidadState extends Equatable {
  const DisponibilidadState({
    this.carga = CargaDisponibilidad.inicial,
    this.ausencias = const [],
    this.disponibleAhora = true,
    this.guardando = false,
    this.falla,
    this.aviso,
  });

  final CargaDisponibilidad carga;
  final List<Ausencia> ausencias;
  final bool disponibleAhora;
  final bool guardando;

  /// Error al cargar: la pantalla muestra el mensaje y un botón Reintentar.
  final DisponibilidadFailure? falla;
  final AvisoDisponibilidad? aviso;

  static const _unset = Object();

  DisponibilidadState copyWith({
    CargaDisponibilidad? carga,
    List<Ausencia>? ausencias,
    bool? disponibleAhora,
    bool? guardando,
    Object? falla = _unset,
    Object? aviso = _unset,
  }) {
    return DisponibilidadState(
      carga: carga ?? this.carga,
      ausencias: ausencias ?? this.ausencias,
      disponibleAhora: disponibleAhora ?? this.disponibleAhora,
      guardando: guardando ?? this.guardando,
      falla: identical(falla, _unset)
          ? this.falla
          : falla as DisponibilidadFailure?,
      aviso: identical(aviso, _unset)
          ? this.aviso
          : aviso as AvisoDisponibilidad?,
    );
  }

  @override
  List<Object?> get props => [
    carga,
    ausencias,
    disponibleAhora,
    guardando,
    falla,
    aviso,
  ];
}
