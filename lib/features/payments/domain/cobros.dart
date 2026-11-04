import 'package:equatable/equatable.dart';

double _numero(Object? v) => switch (v) {
  num n => n.toDouble(),
  String s => double.tryParse(s) ?? 0,
  _ => 0,
};

/// Estado de la retención en garantía simulada (SCRUM-891 y 892).
enum EstadoRetencion {
  retenida,
  liberada,
  otro;

  static EstadoRetencion desde(String? valor) => switch (valor) {
    'RETENIDA' => EstadoRetencion.retenida,
    'LIBERADA' => EstadoRetencion.liberada,
    _ => EstadoRetencion.otro,
  };

  String get etiqueta => switch (this) {
    EstadoRetencion.retenida => 'Retenido en garantía',
    EstadoRetencion.liberada => 'Liberado',
    EstadoRetencion.otro => 'Desconocido',
  };
}

/// Retención de un pago aprobado. Es una simulación: [simulada] viene de Core y
/// nunca se presenta como custodia de dinero real.
class RetencionPago extends Equatable {
  const RetencionPago({
    required this.pagoId,
    required this.monto,
    required this.moneda,
    required this.estado,
    required this.simulada,
    this.creadaEn,
    this.liberadaEn,
  });

  factory RetencionPago.fromJson(Map<String, dynamic> json) => RetencionPago(
    pagoId: (json['pagoId'] as String?) ?? '',
    monto: _numero(json['monto']),
    moneda: (json['moneda'] as String?) ?? 'COP',
    estado: EstadoRetencion.desde(json['estado'] as String?),
    simulada: (json['simulada'] as bool?) ?? true,
    creadaEn: DateTime.tryParse((json['creadaEn'] as String?) ?? '')?.toLocal(),
    liberadaEn: DateTime.tryParse(
      (json['liberadaEn'] as String?) ?? '',
    )?.toLocal(),
  );

  final String pagoId;
  final double monto;
  final String moneda;
  final EstadoRetencion estado;
  final bool simulada;
  final DateTime? creadaEn;
  final DateTime? liberadaEn;

  @override
  List<Object?> get props => [
    pagoId,
    monto,
    moneda,
    estado,
    simulada,
    creadaEn,
    liberadaEn,
  ];
}

/// Liquidación simulada al aliado: bruto = comisión + neto.
class LiquidacionAliado extends Equatable {
  const LiquidacionAliado({
    required this.montoBruto,
    required this.porcentajeComision,
    required this.comision,
    required this.montoNeto,
  });

  factory LiquidacionAliado.fromJson(Map<String, dynamic> json) =>
      LiquidacionAliado(
        montoBruto: _numero(json['montoBruto']),
        porcentajeComision: _numero(json['porcentajeComision']),
        comision: _numero(json['comision']),
        montoNeto: _numero(json['montoNeto']),
      );

  final double montoBruto;
  final double porcentajeComision;
  final double comision;
  final double montoNeto;

  @override
  List<Object?> get props => [
    montoBruto,
    porcentajeComision,
    comision,
    montoNeto,
  ];
}

/// Un cobro del aliado: la retención de un pago y, si ya se liberó, su
/// liquidación.
class CobroAliado extends Equatable {
  const CobroAliado({required this.retencion, this.liquidacion});

  factory CobroAliado.fromJson(Map<String, dynamic> json) {
    final liq = json['liquidacion'];
    return CobroAliado(
      retencion: RetencionPago.fromJson(json),
      liquidacion: liq is Map
          ? LiquidacionAliado.fromJson(Map<String, dynamic>.from(liq))
          : null,
    );
  }

  final RetencionPago retencion;
  final LiquidacionAliado? liquidacion;

  @override
  List<Object?> get props => [retencion, liquidacion];
}
