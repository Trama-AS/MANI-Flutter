import 'package:equatable/equatable.dart';

/// Lo que Rules decidió sobre una cotización frente a la tarifa que regía al
/// emitirla (HU-M06-02 / SCRUM-866). `sinTarifa` lo dice Core sin llamar a
/// Rules: no hay rango contra el cual comparar.
enum ResultadoTarifa { dentroDeRango, porDebajo, porEncima, sinTarifa }

ResultadoTarifa _resultado(Object? v) => switch (v) {
  'DENTRO_DE_RANGO' => ResultadoTarifa.dentroDeRango,
  'POR_DEBAJO' => ResultadoTarifa.porDebajo,
  'POR_ENCIMA' => ResultadoTarifa.porEncima,
  'SIN_TARIFA' => ResultadoTarifa.sinTarifa,
  // Un resultado desconocido no se adivina: se trata como respuesta inválida.
  _ => throw FormatException('Resultado de tarifa desconocido: $v'),
};

double? _numero(Object? v) => v is num ? v.toDouble() : null;

/// Evaluación de una cotización contra la tarifa de referencia (SCRUM-866).
///
/// La ven el cliente dueño y el aliado asignado (alerta bidireccional). Solo
/// informa: la cotización no cambia por esta evaluación (C1).
class EvaluacionTarifa extends Equatable {
  const EvaluacionTarifa({
    required this.cotizacionId,
    required this.resultado,
    required this.total,
    this.desviacionPorcentaje,
    this.valorMin,
    this.valorTipico,
    this.valorMax,
    this.moneda,
  });

  factory EvaluacionTarifa.fromJson(Map<String, dynamic> json) {
    final resultado = _resultado(json['resultado']);
    final tarifa = json['tarifa'] is Map
        ? Map<String, dynamic>.from(json['tarifa'] as Map)
        : null;
    if (resultado != ResultadoTarifa.sinTarifa && tarifa == null) {
      throw const FormatException('Evaluación sin la tarifa de referencia');
    }
    return EvaluacionTarifa(
      cotizacionId: json['cotizacionId'] as String,
      resultado: resultado,
      total: _numero(json['total']) ?? 0,
      desviacionPorcentaje: _numero(json['desviacionPorcentaje']),
      valorMin: _numero(tarifa?['valorMin']),
      valorTipico: _numero(tarifa?['valorTipico']),
      valorMax: _numero(tarifa?['valorMax']),
      moneda: tarifa?['moneda'] as String?,
    );
  }

  final String cotizacionId;
  final ResultadoTarifa resultado;
  final double total;
  final double? desviacionPorcentaje;
  final double? valorMin;
  final double? valorTipico;
  final double? valorMax;
  final String? moneda;

  /// Fuera de banda, por encima o por debajo.
  bool get alerta =>
      resultado == ResultadoTarifa.porDebajo ||
      resultado == ResultadoTarifa.porEncima;

  @override
  List<Object?> get props => [
    cotizacionId,
    resultado,
    total,
    desviacionPorcentaje,
    valorMin,
    valorTipico,
    valorMax,
    moneda,
  ];
}
