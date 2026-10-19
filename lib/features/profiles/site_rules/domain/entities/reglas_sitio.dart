import 'package:equatable/equatable.dart';

/// Reglas contextuales de ingreso y operación configuradas para un sitio y visibles para el aliado
/// (US-02.2.3 / SCRUM-853).
///
/// El JSON es exactamente el objeto `SiteRules` de Core (MANI-Node#12), documentado en
/// `ModeloDatos.md` (`sitio.reglas`):
/// `{ horario: { inicio, fin, diasPermitidos }, permisosRequeridos, elementosProteccion,
///    instruccionesIngreso, requiereAprobacionPrevia, contactoAcceso: { nombre, telefono } }`.
/// `horario` es opcional: sin él el sitio no tiene restricción horaria.
class ReglasContextualesSitio extends Equatable {
  const ReglasContextualesSitio({
    required this.siteId,
    this.horarioPermitido,
    this.diasPermitidos = diasHabiles,
    this.permisosRequeridos = const [],
    this.elementosProteccion = const [],
    this.instruccionesIngreso,
    this.requiereAprobacionPrevia = false,
    this.contactoAcceso,
  });

  static const diasHabiles = ['LUN', 'MAR', 'MIE', 'JUE', 'VIE'];

  final String siteId;

  /// Horario en texto para la UI (`HH:mm - HH:mm`); null si el sitio no restringe horario.
  final String? horarioPermitido;
  final List<String> diasPermitidos;
  final List<String> permisosRequeridos;
  final List<String> elementosProteccion;
  final String? instruccionesIngreso;
  final bool requiereAprobacionPrevia;
  final Map<String, dynamic>? contactoAcceso;

  /// En la UI la casilla "Requiere EPP" equivale a tener elementos de protección.
  bool get requiereEpp => elementosProteccion.isNotEmpty;

  /// Nombre que usa la UI para los permisos exigidos en portería.
  List<String> get documentosRequeridos => permisosRequeridos;

  static List<String> _lista(Object? raw) =>
      raw is List ? raw.map((e) => e.toString()).toList() : const <String>[];

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
    var dias = diasHabiles;
    if (reglas['horario'] is Map) {
      final h = reglas['horario'] as Map;
      if (h['inicio'] != null && h['fin'] != null) {
        horarioTexto = '${h['inicio']} - ${h['fin']}';
      }
      final rawDias = _lista(h['diasPermitidos']);
      if (rawDias.isNotEmpty) dias = rawDias;
    }

    return ReglasContextualesSitio(
      siteId: (data['id'] ?? data['siteId'] ?? siteId).toString(),
      horarioPermitido: horarioTexto,
      diasPermitidos: dias,
      permisosRequeridos: _lista(reglas['permisosRequeridos']),
      elementosProteccion: _lista(reglas['elementosProteccion']),
      instruccionesIngreso: reglas['instruccionesIngreso']?.toString(),
      requiereAprobacionPrevia:
          (reglas['requiereAprobacionPrevia'] as bool?) ?? false,
      contactoAcceso: reglas['contactoAcceso'] is Map
          ? Map<String, dynamic>.from(reglas['contactoAcceso'] as Map)
          : null,
    );
  }

  /// Convierte `HH:mm - HH:mm` al objeto `horario` de Core; null si no hay horario válido.
  Map<String, dynamic>? _horario() {
    final texto = horarioPermitido;
    if (texto == null || !texto.contains('-')) return null;
    final partes = texto.split('-');
    if (partes.length != 2) return null;
    final inicio = partes[0].replaceAll(RegExp(r'[^0-9:]'), '').trim();
    final fin = partes[1].replaceAll(RegExp(r'[^0-9:]'), '').trim();
    if (inicio.isEmpty || fin.isEmpty) return null;
    return {
      'inicio': inicio.padLeft(5, '0'),
      'fin': fin.padLeft(5, '0'),
      'diasPermitidos': diasPermitidos,
    };
  }

  Map<String, dynamic> toPayload() {
    final horario = _horario();
    final instrucciones = instruccionesIngreso?.trim();
    return {
      'reglas': {
        'horario': ?horario,
        'permisosRequeridos': permisosRequeridos,
        'elementosProteccion': elementosProteccion,
        if (instrucciones != null && instrucciones.isNotEmpty)
          'instruccionesIngreso': instrucciones,
        'requiereAprobacionPrevia': requiereAprobacionPrevia,
        if (contactoAcceso != null) 'contactoAcceso': contactoAcceso,
      },
    };
  }

  @override
  List<Object?> get props => [
    siteId,
    horarioPermitido,
    diasPermitidos,
    permisosRequeridos,
    elementosProteccion,
    instruccionesIngreso,
    requiereAprobacionPrevia,
    contactoAcceso,
  ];
}
