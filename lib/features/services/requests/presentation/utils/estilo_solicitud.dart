import 'package:flutter/material.dart';

import '../../domain/entities/catalogo_solicitud.dart';

/// Ícono representativo de una categoría a partir de su nombre. Las
/// categorías las crea cada tenant con nombres libres (US-03.1.1), así que
/// se reconocen palabras clave y el resto usa un ícono genérico.
IconData iconoCategoria(String nombre) {
  final n = nombre.toLowerCase();
  bool tiene(List<String> claves) => claves.any(n.contains);
  if (tiene(['plomer', 'fuga', 'hidr', 'tuber'])) return Icons.plumbing;
  if (tiene(['electr'])) return Icons.electrical_services;
  if (tiene(['cerraj', 'llave', 'puerta'])) return Icons.key_rounded;
  if (tiene(['pintur'])) return Icons.format_paint_outlined;
  if (tiene(['carpint', 'madera'])) return Icons.carpenter;
  if (tiene(['jardin'])) return Icons.yard_outlined;
  if (tiene(['limpi'])) return Icons.cleaning_services_outlined;
  if (tiene(['aire', 'clima', 'refriger'])) return Icons.ac_unit;
  if (tiene(['gas'])) return Icons.local_fire_department_outlined;
  return Icons.home_repair_service_rounded;
}

/// Qué recibirá el cliente según cómo opera la categoría.
String textoModalidad(ModalidadCobro modalidad) => switch (modalidad) {
  ModalidadCobro.cotizacionPrevia => 'Recibirás cotizaciones de los aliados',
  ModalidadCobro.tarifaEstandar => 'Precio fijo de referencia',
  ModalidadCobro.desconocida => 'Te contactará un aliado verificado',
};
