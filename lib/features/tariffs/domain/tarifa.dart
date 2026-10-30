import 'package:equatable/equatable.dart';

double _numero(Object? v) => v is num ? v.toDouble() : double.parse('$v');

DateTime? _fecha(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Una versión de la tarifa de referencia de una categoría (HU-M10-01 /
/// SCRUM-885). Las versiones son inmutables: editar crea la siguiente y deja
/// esta en [estado] `REEMPLAZADA`.
class Tarifa extends Equatable {
  const Tarifa({
    required this.id,
    required this.categoriaId,
    required this.categoriaNombre,
    required this.valorMin,
    required this.valorTipico,
    required this.valorMax,
    required this.moneda,
    required this.vigenciaDesde,
    required this.version,
    this.vigenciaHasta,
    this.condiciones,
    this.estado = 'ACTIVA',
    this.creadaEn,
  });

  factory Tarifa.fromJson(Map<String, dynamic> json) {
    final auditoria = json['auditoria'];
    return Tarifa(
      id: json['id'] as String,
      categoriaId: json['categoriaId'] as String,
      categoriaNombre: (json['categoriaNombre'] as String?) ?? '',
      valorMin: _numero(json['valorMin']),
      valorTipico: _numero(json['valorTipico']),
      valorMax: _numero(json['valorMax']),
      moneda: (json['moneda'] as String?) ?? 'COP',
      vigenciaDesde: json['vigenciaDesde'] as String,
      vigenciaHasta: json['vigenciaHasta'] as String?,
      condiciones: json['condiciones'] as String?,
      version: (json['version'] as num).toInt(),
      estado: (json['estado'] as String?) ?? 'ACTIVA',
      creadaEn: auditoria is Map ? _fecha(auditoria['creadaEn']) : null,
    );
  }

  final String id;
  final String categoriaId;
  final String categoriaNombre;
  final double valorMin;
  final double valorTipico;
  final double valorMax;
  final String moneda;

  /// `YYYY-MM-DD`, inclusive.
  final String vigenciaDesde;

  /// `YYYY-MM-DD`, inclusive; `null` = sin fecha de fin.
  final String? vigenciaHasta;
  final String? condiciones;
  final int version;
  final String estado;
  final DateTime? creadaEn;

  bool get activa => estado == 'ACTIVA';

  String get vigencia =>
      'Desde $vigenciaDesde${vigenciaHasta == null ? ' (sin fin)' : ' hasta $vigenciaHasta'}';

  @override
  List<Object?> get props => [
    id,
    categoriaId,
    valorMin,
    valorTipico,
    valorMax,
    moneda,
    vigenciaDesde,
    vigenciaHasta,
    condiciones,
    version,
    estado,
  ];
}

/// Datos que el administrador envía al cargar o editar una tarifa. Core
/// vuelve a validarlos; la app solo evita enviar lo que sabe que no pasa.
class DatosTarifa extends Equatable {
  const DatosTarifa({
    required this.valorMin,
    required this.valorTipico,
    required this.valorMax,
    this.moneda = 'COP',
    this.vigenciaDesde,
    this.vigenciaHasta,
    this.condiciones,
  });

  final double valorMin;
  final double valorTipico;
  final double valorMax;
  final String moneda;
  final String? vigenciaDesde;
  final String? vigenciaHasta;
  final String? condiciones;

  /// Mismas reglas que Core (C2 de SCRUM-885); `null` si la tarifa es válida.
  String? get error {
    if (valorMin < 0 || valorTipico < 0 || valorMax < 0) {
      return 'Los valores no pueden ser negativos.';
    }
    if (!(valorMin <= valorTipico && valorTipico <= valorMax)) {
      return 'Debe cumplirse mínimo ≤ típico ≤ máximo.';
    }
    if (!(valorMin < valorMax)) {
      return 'El mínimo debe ser menor que el máximo.';
    }
    final desde = vigenciaDesde, hasta = vigenciaHasta;
    if (desde != null && hasta != null && hasta.compareTo(desde) < 0) {
      return 'La vigencia no puede terminar antes de empezar.';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'valorMin': valorMin,
    'valorTipico': valorTipico,
    'valorMax': valorMax,
    'moneda': moneda,
    'vigenciaDesde': ?vigenciaDesde,
    'vigenciaHasta': ?vigenciaHasta,
    'condiciones': ?condiciones,
  };

  @override
  List<Object?> get props => [
    valorMin,
    valorTipico,
    valorMax,
    moneda,
    vigenciaDesde,
    vigenciaHasta,
    condiciones,
  ];
}

/// Tarifa vigente de la categoría de una solicitud al cotizar (HU-M10-02 /
/// SCRUM-886). Sin tarifa vigente [tarifa] es `null`: la app dice que no hay
/// referencia y nunca muestra un valor por defecto (C2).
class ReferenciaTarifa extends Equatable {
  const ReferenciaTarifa({this.tarifa});

  factory ReferenciaTarifa.fromJson(Map<String, dynamic> json) {
    final t = json['tarifa'];
    return ReferenciaTarifa(
      tarifa: json['disponible'] == true && t is Map
          ? Tarifa.fromJson(Map<String, dynamic>.from(t))
          : null,
    );
  }

  final Tarifa? tarifa;

  bool get disponible => tarifa != null;

  @override
  List<Object?> get props => [tarifa];
}

/// Una cotización que Rules evaluó fuera del rango de su tarifa (SCRUM-887).
class CotizacionFueraDeRango extends Equatable {
  const CotizacionFueraDeRango({
    required this.id,
    required this.solicitudId,
    required this.categoria,
    required this.aliado,
    required this.total,
    required this.tarifaMin,
    required this.tarifaMax,
    required this.tarifaVersion,
    required this.porEncima,
    required this.desviacionPorcentaje,
    this.creadaEn,
  });

  factory CotizacionFueraDeRango.fromJson(Map<String, dynamic> json) {
    final tarifa = Map<String, dynamic>.from(json['tarifa'] as Map);
    return CotizacionFueraDeRango(
      id: json['id'] as String,
      solicitudId: json['solicitudId'] as String,
      categoria: (json['categoria'] as Map?)?['nombre'] as String? ?? '',
      aliado: (json['aliado'] as Map?)?['nombre'] as String? ?? '',
      total: _numero(json['total']),
      tarifaMin: _numero(tarifa['valorMin']),
      tarifaMax: _numero(tarifa['valorMax']),
      tarifaVersion: (tarifa['version'] as num).toInt(),
      porEncima: json['resultado'] == 'POR_ENCIMA',
      desviacionPorcentaje: _numero(json['desviacionPorcentaje']),
      creadaEn: _fecha(json['creadaEn']),
    );
  }

  final String id;
  final String solicitudId;
  final String categoria;
  final String aliado;
  final double total;
  final double tarifaMin;
  final double tarifaMax;
  final int tarifaVersion;
  final bool porEncima;
  final double desviacionPorcentaje;
  final DateTime? creadaEn;

  @override
  List<Object?> get props => [id, total, porEncima, desviacionPorcentaje];
}

/// Reporte de cotizaciones fuera de rango del periodo (HU-M10-03 / SCRUM-887).
class ReporteFueraDeRango extends Equatable {
  const ReporteFueraDeRango({
    required this.cotizaciones,
    required this.evaluadas,
    required this.sinTarifa,
    required this.totalCotizaciones,
    this.reglasVersion,
  });

  factory ReporteFueraDeRango.fromJson(Map<String, dynamic> json) {
    final totales = Map<String, dynamic>.from(json['totales'] as Map);
    return ReporteFueraDeRango(
      cotizaciones: [
        for (final c in (json['cotizaciones'] as List? ?? const []))
          CotizacionFueraDeRango.fromJson(Map<String, dynamic>.from(c as Map)),
      ],
      evaluadas: (totales['evaluadas'] as num).toInt(),
      sinTarifa: (totales['sinTarifa'] as num).toInt(),
      totalCotizaciones: (totales['cotizaciones'] as num).toInt(),
      reglasVersion: json['reglasVersion'] as String?,
    );
  }

  final List<CotizacionFueraDeRango> cotizaciones;
  final int evaluadas;
  final int sinTarifa;
  final int totalCotizaciones;
  final String? reglasVersion;

  @override
  List<Object?> get props => [
    cotizaciones,
    evaluadas,
    sinTarifa,
    totalCotizaciones,
    reglasVersion,
  ];
}
