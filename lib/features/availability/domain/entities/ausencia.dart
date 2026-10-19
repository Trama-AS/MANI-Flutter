import 'package:equatable/equatable.dart';

/// Motivo por el que el aliado se marca "No disponible" (US-02.1.6).
/// El nombre de cada valor coincide con el catálogo de Core (`reason`).
enum MotivoAusencia {
  vacaciones('VACACIONES', 'Vacaciones'),
  enfermedad('ENFERMEDAD', 'Enfermedad'),
  otro('OTRO', 'Otro');

  const MotivoAusencia(this.codigo, this.etiqueta);

  final String codigo;
  final String etiqueta;

  static MotivoAusencia desdeCodigo(String? codigo) => MotivoAusencia.values
      .firstWhere((m) => m.codigo == codigo, orElse: () => MotivoAusencia.otro);
}

/// Intervalo [inicio, fin) en el que el aliado no recibe solicitudes.
class Ausencia extends Equatable {
  const Ausencia({
    required this.id,
    required this.inicio,
    required this.fin,
    required this.motivo,
    this.nota,
    this.activa = false,
  });

  final String id;
  final DateTime inicio;
  final DateTime fin;
  final MotivoAusencia motivo;
  final String? nota;

  /// true si la ausencia cubre el instante actual según el servidor.
  final bool activa;

  @override
  List<Object?> get props => [id, inicio, fin, motivo, nota, activa];
}

/// Datos que el aliado llena en el formulario, antes de que el servidor
/// asigne un id.
class BorradorAusencia extends Equatable {
  const BorradorAusencia({
    required this.inicio,
    required this.fin,
    required this.motivo,
    this.nota,
  });

  final DateTime inicio;
  final DateTime fin;
  final MotivoAusencia motivo;
  final String? nota;

  /// Mismas reglas que Core (MANI-AUS-422H), para avisar antes de enviar.
  /// Devuelve el mensaje del primer problema o `null` si es válido.
  String? validar(DateTime ahora) {
    if (!fin.isAfter(inicio)) {
      return 'La fecha de fin debe ser posterior a la de inicio.';
    }
    if (!fin.isAfter(ahora)) {
      return 'La ausencia debe terminar en el futuro.';
    }
    if (fin.difference(inicio) > const Duration(days: 365)) {
      return 'Una ausencia no puede durar más de 365 días.';
    }
    if ((nota ?? '').trim().length > 280) {
      return 'La nota admite máximo 280 caracteres.';
    }
    return null;
  }

  @override
  List<Object?> get props => [inicio, fin, motivo, nota];
}

/// Respuesta del listado: ausencias vigentes/futuras y estado actual.
class DisponibilidadAliado extends Equatable {
  const DisponibilidadAliado({
    required this.ausencias,
    required this.disponibleAhora,
  });

  final List<Ausencia> ausencias;
  final bool disponibleAhora;

  @override
  List<Object?> get props => [ausencias, disponibleAhora];
}
