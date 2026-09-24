import 'package:equatable/equatable.dart';

import '../failures/verificacion_failure.dart';

/// Decisión del administrador sobre un aliado. Se construye solo a través de
/// sus fábricas, que aplican las mismas reglas que la RPC
/// `resolver_verificacion_aliado` para fallar rápido y sin red.
sealed class DecisionVerificacion extends Equatable {
  const DecisionVerificacion();

  static const int motivoMinimo = 10;
  static const int motivoMaximo = 500;

  const factory DecisionVerificacion.aprobar() = Aprobacion;

  /// Lanza [VerificacionFailure] con tipo `motivoInvalido` si el motivo no
  /// cumple la longitud exigida.
  factory DecisionVerificacion.rechazar(String motivo) {
    final limpio = motivo.trim();
    if (limpio.length < motivoMinimo || limpio.length > motivoMaximo) {
      throw const VerificacionFailure(VerificacionErrorTipo.motivoInvalido);
    }
    return Rechazo._(limpio);
  }
}

final class Aprobacion extends DecisionVerificacion {
  const Aprobacion();

  @override
  List<Object?> get props => const [];
}

final class Rechazo extends DecisionVerificacion {
  const Rechazo._(this.motivo);

  final String motivo;

  @override
  List<Object?> get props => [motivo];
}
