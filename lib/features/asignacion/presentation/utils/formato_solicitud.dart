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

/// Traduce las reglas conocidas de `sitio.reglas` a lenguaje claro; las
/// desconocidas se muestran con su clave legible para no ocultar ninguna
/// (QS-06 exige el 100% de las reglas visibles antes de aceptar).
DescripcionRegla describirRegla(ReglaSitio regla) {
  final v = regla.valor;
  switch ((regla.clave, v)) {
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
    _ => (icono: Icons.schedule, texto: '$nombre: $v', advertencia: true),
  };
}

/// "horario_acceso" → "Horario acceso".
String _legible(String clave) {
  final t = clave.replaceAll('_', ' ').trim();
  return t.isEmpty ? clave : '${t[0].toUpperCase()}${t.substring(1)}';
}
