/// Fecha y hora cortas para las listas (`04/11/2026 14:05`), sin depender de
/// `intl`. Recibe la hora local; con `null` devuelve un guion.
String formatearFechaHora(DateTime? fecha) {
  if (fecha == null) return '—';
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(fecha.day)}/${dos(fecha.month)}/${fecha.year} '
      '${dos(fecha.hour)}:${dos(fecha.minute)}';
}
