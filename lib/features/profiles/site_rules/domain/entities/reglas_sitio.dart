import 'package:equatable/equatable.dart';

/// Reglas contextuales de ingreso y operación configuradas por el cliente
/// corporativo en un sitio y visibles para el aliado (US-02.2.3 / SCRUM-853).
class ReglasContextualesSitio extends Equatable {
  const ReglasContextualesSitio({
    required this.siteId,
    this.requiereEpp = false,
    this.horarioPermitido,
    this.documentosRequeridos = const [],
    this.permisosRequeridos = const [],
    this.elementosProteccion = const [],
    this.instruccionesIngreso,
    this.requiereAprobacionPrevia = false,
    this.contactoAcceso,
    this.notasAdicionales,
  });

  final String siteId;
  final bool requiereEpp;
  final String? horarioPermitido;
  final List<String> documentosRequeridos;
  final List<String> permisosRequeridos;
  final List<String> elementosProteccion;
  final String? instruccionesIngreso;
  final bool requiereAprobacionPrevia;
  final Map<String, dynamic>? contactoAcceso;
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

    String? horarioTexto;
    if (reglas['horario'] is Map) {
      final h = reglas['horario'] as Map;
      final inicio = h['inicio']?.toString() ?? '08:00';
      final fin = h['fin']?.toString() ?? '17:00';
      horarioTexto = '$inicio - $fin';
    } else {
      horarioTexto = reglas['horarioPermitido']?.toString();
    }

    final rawPermisos = reglas['permisosRequeridos'] ??
        reglas['documentosRequeridos'] ??
        const [];
    final docs = rawPermisos is List
        ? rawPermisos.map((e) => e.toString()).toList()
        : <String>[];

    final rawEpp = reglas['elementosProteccion'] ?? const [];
    final epp = rawEpp is List
        ? rawEpp.map((e) => e.toString()).toList()
        : <String>[];
    final reqEpp = (reglas['requiereEpp'] as bool?) ?? epp.isNotEmpty;

    return ReglasContextualesSitio(
      siteId: (data['id'] ?? data['siteId'] ?? siteId).toString(),
      requiereEpp: reqEpp,
      horarioPermitido: horarioTexto,
      documentosRequeridos: docs,
      permisosRequeridos: docs,
      elementosProteccion: epp,
      instruccionesIngreso: reglas['instruccionesIngreso']?.toString(),
      requiereAprobacionPrevia:
          (reglas['requiereAprobacionPrevia'] as bool?) ?? false,
      contactoAcceso: reglas['contactoAcceso'] is Map
          ? Map<String, dynamic>.from(reglas['contactoAcceso'] as Map)
          : null,
      notasAdicionales: reglas['notasAdicionales']?.toString(),
    );
  }

  Map<String, dynamic> toPayload() {
    Map<String, dynamic>? horarioMap;
    if (horarioPermitido != null && horarioPermitido!.contains('-')) {
      final parts = horarioPermitido!.split('-');
      if (parts.length == 2) {
        final inicio = parts[0].replaceAll(RegExp(r'[^0-9:]'), '').trim();
        final fin = parts[1].replaceAll(RegExp(r'[^0-9:]'), '').trim();
        if (inicio.isNotEmpty && fin.isNotEmpty) {
          horarioMap = {
            'inicio': inicio.padLeft(5, '0'),
            'fin': fin.padLeft(5, '0'),
            'diasPermitidos': const ['LUN', 'MAR', 'MIE', 'JUE', 'VIE'],
          };
        }
      }
    }
    horarioMap ??= const {
      'inicio': '08:00',
      'fin': '17:00',
      'diasPermitidos': ['LUN', 'MAR', 'MIE', 'JUE', 'VIE'],
    };

    final eppList = elementosProteccion.isNotEmpty
        ? elementosProteccion
        : (requiereEpp
            ? const ['Casco', 'Botas de seguridad']
            : const <String>[]);

    return {
      'reglas': {
        'horario': horarioMap,
        'permisosRequeridos': permisosRequeridos.isNotEmpty
            ? permisosRequeridos
            : documentosRequeridos,
        'elementosProteccion': eppList,
        'instruccionesIngreso': instruccionesIngreso ?? '',
        'requiereAprobacionPrevia': requiereAprobacionPrevia,
        if (contactoAcceso != null) 'contactoAcceso': contactoAcceso,
        'requiereEpp': requiereEpp || eppList.isNotEmpty,
        'horarioPermitido': horarioPermitido,
        'documentosRequeridos': documentosRequeridos,
      },
    };
  }

  @override
  List<Object?> get props => [
    siteId,
    requiereEpp,
    horarioPermitido,
    documentosRequeridos,
    permisosRequeridos,
    elementosProteccion,
    instruccionesIngreso,
    requiereAprobacionPrevia,
    contactoAcceso,
    notasAdicionales,
  ];
}
