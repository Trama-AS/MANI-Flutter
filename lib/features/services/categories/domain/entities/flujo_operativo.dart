/// Cómo opera una categoría de servicio del tenant (US-03.1.1).
///
/// Define qué pasos recorre una solicitud de esa categoría antes de que el
/// aliado ejecute el trabajo. El valor se guarda en
/// `categoria_servicio.flujo_operativo`.
enum FlujoOperativo {
  /// El aliado diagnostica y envía una cotización que el cliente acepta antes
  /// de empezar (RF-15/RF-17). Para trabajos cuyo costo depende del caso.
  cotizacionPrevia(
    codigo: 'COTIZACION_PREVIA',
    etiqueta: 'Cotización previa',
    descripcion:
        'El aliado revisa el caso y envía una cotización. El cliente la acepta antes de empezar.',
    ejemplo: 'Ideal para plomería, electricidad o reparaciones.',
  ),

  /// Se cobra con la tarifa de referencia del tenant, sin cotización (RF-22).
  /// Para servicios de precio conocido.
  tarifaEstandar(
    codigo: 'TARIFA_ESTANDAR',
    etiqueta: 'Tarifa estándar',
    descripcion:
        'El servicio tiene un precio fijo de referencia. El cliente lo solicita sin esperar cotización.',
    ejemplo: 'Ideal para apertura de puertas o instalaciones sencillas.',
  );

  const FlujoOperativo({
    required this.codigo,
    required this.etiqueta,
    required this.descripcion,
    required this.ejemplo,
  });

  /// Valor persistido en BD.
  final String codigo;
  final String etiqueta;
  final String descripcion;
  final String ejemplo;

  /// `null` si el valor de BD no corresponde a ningún flujo conocido.
  static FlujoOperativo? desde(String? valor) {
    final v = valor?.trim().toUpperCase();
    for (final f in values) {
      if (f.codigo == v) {
        return f;
      }
    }
    return null;
  }
}
