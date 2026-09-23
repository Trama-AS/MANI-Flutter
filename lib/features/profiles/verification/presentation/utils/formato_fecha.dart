const _meses = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// "22 sep 2026"
String fechaCorta(DateTime fecha) =>
    '${fecha.day} ${_meses[fecha.month - 1]} ${fecha.year}';

/// "Hoy", "Ayer", "Hace 3 días".
String haceCuanto(DateTime fecha, DateTime ahora) {
  final dias = DateTime(
    ahora.year,
    ahora.month,
    ahora.day,
  ).difference(DateTime(fecha.year, fecha.month, fecha.day)).inDays;
  if (dias <= 0) return 'Hoy';
  if (dias == 1) return 'Ayer';
  return 'Hace $dias días';
}
