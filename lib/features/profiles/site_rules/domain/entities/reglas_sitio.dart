import 'package:equatable/equatable.dart';

/// Reglas contextuales de ingreso y operación configuradas por el cliente
/// corporativo en un sitio y visibles para el aliado (US-02.2.3 / SCRUM-853).
class ReglasContextualesSitio extends Equatable {
  const ReglasContextualesSitio({
    required this.siteId,
    this.requiereEpp = false,
    this.horarioPermitido,
    this.documentosRequeridos = const [],
    this.instruccionesIngreso,
    this.notasAdicionales,
  });

  final String siteId;
  final bool requiereEpp;
  final String? horarioPermitido;
  final List<String> documentosRequeridos;
  final String? instruccionesIngreso;
  final String? notasAdicionales;

  factory ReglasContextualesSitio.fromJson(
    String siteId,
    Map<String, dynamic> json,
  ) {
    final data = (json['data'] is Map<String, dynamic>)
        ? json['data'] as Map<String, dynamic>
        : json;
    final reglas = (data['reglas'] is Map<String, dynamic>)
        ? data['reglas'] as Map<String, dynamic>
        : data;
    final rawDocs = reglas['documentosRequeridos'] ?? const [];

    return ReglasContextualesSitio(
      siteId: (data['id'] ?? data['siteId'] ?? siteId).toString(),
      requiereEpp: reglas['requiereEpp'] as bool? ?? false,
      horarioPermitido: reglas['horarioPermitido']?.toString(),
      documentosRequeridos: rawDocs is List
          ? rawDocs.map((e) => e.toString()).toList()
          : const [],
      instruccionesIngreso: reglas['instruccionesIngreso']?.toString(),
      notasAdicionales: reglas['notasAdicionales']?.toString(),
    );
  }

  Map<String, dynamic> toPayload() {
    return {
      'reglas': {
        'requiereEpp': requiereEpp,
        if (horarioPermitido != null && horarioPermitido!.trim().isNotEmpty)
          'horarioPermitido': horarioPermitido!.trim(),
        'documentosRequeridos': documentosRequeridos,
        if (instruccionesIngreso != null &&
            instruccionesIngreso!.trim().isNotEmpty)
          'instruccionesIngreso': instruccionesIngreso!.trim(),
        if (notasAdicionales != null && notasAdicionales!.trim().isNotEmpty)
          'notasAdicionales': notasAdicionales!.trim(),
      },
    };
  }

  @override
  List<Object?> get props => [
    siteId,
    requiereEpp,
    horarioPermitido,
    documentosRequeridos,
    instruccionesIngreso,
    notasAdicionales,
  ];
}
