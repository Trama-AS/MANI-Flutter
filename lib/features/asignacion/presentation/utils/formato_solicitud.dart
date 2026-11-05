import 'package:flutter/material.dart';

import '../../domain/entities/regla_sitio.dart';

/// "Hace un momento", "Hace 12 min", "Hace 3 h", "Hace 2 días".
String haceCuanto(DateTime fecha, DateTime ahora) {
  final d = ahora.difference(fecha);
  if (d.inMinutes < 1) {
    return 'Hace un momento';
  }
  if (d.inMinutes < 60) {
    return 'Hace ${d.inMinutes} min';
  }
  if (d.inHours < 24) {
    return 'Hace ${d.inHours} h';
  }
  return d.inDays == 1 ? 'Hace 1 día' : 'Hace ${d.inDays} días';
}

/// Cómo mostrar una regla del sitio: ícono, texto y si limita al aliado.
typedef DescripcionRegla = ({IconData icono, String texto, bool advertencia});

/// Reglas que solo ve el aliado asignado (SCRUM-1388, decisión de la PO):
/// en la oferta se muestran los requisitos; el contacto de acceso y las
/// instrucciones de ingreso, solo después de la asignación. Core ya no las
/// envía en la oferta; este filtro es la segunda barrera en pantalla.
const reglasSoloAsignado = {'contactoAcceso', 'instruccionesIngreso'};

/// Reglas del sitio que se muestran en la tarjeta: sin las de acceso si la
/// solicitud no es del aliado, y sin las vacías (lista vacía, `null`, texto
/// en blanco o `requiereAprobacionPrevia: false`), que no dicen nada.
List<ReglaSitio> reglasParaMostrar(
  List<ReglaSitio> reglas, {
  required bool asignado,
}) => [
  for (final r in reglas)
    if ((asignado || !reglasSoloAsignado.contains(r.clave)) && !_vacia(r)) r,
];

bool _vacia(ReglaSitio r) => switch (r.valor) {
  null => true,
  final String t => t.trim().isEmpty,
  final List<dynamic> l => l.isEmpty,
  final Map<dynamic, dynamic> m => m.values.every(
    (v) => v == null || (v is String && v.trim().isEmpty),
  ),
  false => r.clave == 'requiereAprobacionPrevia',
  _ => false,
};

/// Traduce las reglas conocidas de `sitio.reglas` a lenguaje claro; las
/// desconocidas se muestran con su clave legible y sin formato técnico.
DescripcionRegla describirRegla(ReglaSitio regla) {
  final v = regla.valor;
  switch ((regla.clave, v)) {
    case ('horario', final Map<dynamic, dynamic> h):
      return (
        icono: Icons.schedule,
        texto: describirHorario(h),
        advertencia: true,
      );
    case ('permisosRequeridos', final List<dynamic> l):
      return (
        icono: Icons.badge_outlined,
        texto: 'Permisos requeridos: ${_enumerar(l)}',
        advertencia: true,
      );
    case ('elementosProteccion', final List<dynamic> l):
      return (
        icono: Icons.health_and_safety_outlined,
        texto: 'Protección obligatoria: ${_enumerar(l)}',
        advertencia: true,
      );
    case ('requiereAprobacionPrevia', true):
      return (
        icono: Icons.verified_user_outlined,
        texto: 'Requiere aprobación previa para ingresar',
        advertencia: true,
      );
    case ('instruccionesIngreso', final String t):
      return (
        icono: Icons.login,
        texto: 'Instrucciones de ingreso: ${t.trim()}',
        advertencia: false,
      );
    case ('contactoAcceso', final Map<dynamic, dynamic> c):
      final partes = [
        for (final k in ['nombre', 'telefono'])
          if (c[k] is String && (c[k] as String).trim().isNotEmpty)
            (c[k] as String).trim(),
      ];
      return (
        icono: Icons.phone_outlined,
        texto: 'Contacto de acceso: ${partes.join(' · ')}',
        advertencia: false,
      );
    case ('mascotas', true):
      return (icono: Icons.pets, texto: 'Hay mascotas', advertencia: true);
    case ('mascotas', false):
      return (icono: Icons.pets, texto: 'Sin mascotas', advertencia: false);
    case ('parqueadero', true):
      return (
        icono: Icons.local_parking,
        texto: 'Parqueadero disponible',
        advertencia: false,
      );
    case ('parqueadero', false):
      return (
        icono: Icons.local_parking,
        texto: 'Sin parqueadero',
        advertencia: true,
      );
    case ('seguridad_privada', true):
      return (
        icono: Icons.shield_outlined,
        texto: 'Registro en portería',
        advertencia: true,
      );
  }
  final nombre = _legible(regla.clave);
  return switch (v) {
    true => (icono: Icons.info_outline, texto: nombre, advertencia: true),
    false => (
      icono: Icons.info_outline,
      texto: 'Sin ${nombre.toLowerCase()}',
      advertencia: false,
    ),
    null => (icono: Icons.info_outline, texto: nombre, advertencia: false),
    final List<dynamic> l => (
      icono: Icons.info_outline,
      texto: '$nombre: ${_enumerar(l)}',
      advertencia: true,
    ),
    final Map<dynamic, dynamic> m => (
      icono: Icons.info_outline,
      texto: '$nombre: ${_enumerar(m.values.toList())}',
      advertencia: true,
    ),
    _ => (icono: Icons.schedule, texto: '$nombre: $v', advertencia: true),
  };
}

const _dias = ['LUN', 'MAR', 'MIE', 'JUE', 'VIE', 'SAB', 'DOM'];
const _nombreDia = {
  'LUN': 'lunes',
  'MAR': 'martes',
  'MIE': 'miércoles',
  'JUE': 'jueves',
  'VIE': 'viernes',
  'SAB': 'sábado',
  'DOM': 'domingo',
};

/// `{inicio: 08:00, fin: 17:00, diasPermitidos: [LUN..VIE]}` →
/// "Horario: lunes a viernes, de 8:00 a 17:00".
String describirHorario(Map<dynamic, dynamic> h) {
  final crudos = h['diasPermitidos'];
  final unicos = <String>{
    if (crudos is List)
      for (final d in crudos)
        if (d is String && _dias.contains(d.trim().toUpperCase()))
          d.trim().toUpperCase(),
  }.toList()..sort((a, b) => _dias.indexOf(a).compareTo(_dias.indexOf(b)));
  final primero = unicos.isEmpty ? 0 : _dias.indexOf(unicos.first);
  final ultimo = unicos.isEmpty ? 0 : _dias.indexOf(unicos.last);
  final contiguos = unicos.length >= 3 && ultimo - primero == unicos.length - 1;
  final textoDias = switch (unicos.length) {
    0 => null,
    7 => 'todos los días',
    _ when contiguos =>
      '${_nombreDia[unicos.first]} a ${_nombreDia[unicos.last]}',
    _ => _enumerar([for (final d in unicos) _nombreDia[d]]),
  };
  final inicio = _hora(h['inicio']);
  final fin = _hora(h['fin']);
  final partes = [
    ?textoDias,
    if (inicio != null && fin != null) 'de $inicio a $fin',
  ];
  return partes.isEmpty
      ? 'Horario restringido'
      : 'Horario: ${partes.join(', ')}';
}

/// "08:00" → "8:00"; un valor vacío o que no es texto → `null`.
String? _hora(Object? v) {
  if (v is! String || v.trim().isEmpty) {
    return null;
  }
  final t = v.trim();
  return t.length == 5 && t.startsWith('0') ? t.substring(1) : t;
}

/// ["ARL", "Alturas", "Curso"] → "ARL, Alturas y Curso".
String _enumerar(List<dynamic> valores) {
  final l = [
    for (final x in valores)
      if (x != null && '$x'.trim().isNotEmpty) '$x'.trim(),
  ];
  if (l.length <= 1) {
    return l.join();
  }
  return '${l.sublist(0, l.length - 1).join(', ')} y ${l.last}';
}

/// "horario_acceso" → "Horario acceso".
String _legible(String clave) {
  final t = clave.replaceAll('_', ' ').trim();
  return t.isEmpty ? clave : '${t[0].toUpperCase()}${t.substring(1)}';
}
