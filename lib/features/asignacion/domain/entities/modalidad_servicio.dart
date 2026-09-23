/// Cómo se cobra el servicio, según el flujo operativo de su categoría
/// (`categoria_servicio.flujo_operativo`, US-03.1.1). Le dice al aliado, antes
/// de aceptar, si deberá enviar una cotización.
///
/// Es el modelo propio de este contexto: no depende de la feature de
/// categorías, solo comparte los códigos de BD.
enum ModalidadServicio {
  cotizacionPrevia('COTIZACION_PREVIA'),
  tarifaEstandar('TARIFA_ESTANDAR'),
  desconocida('');

  const ModalidadServicio(this.codigo);

  final String codigo;

  static ModalidadServicio desde(String? valor) {
    final v = valor?.trim().toUpperCase();
    for (final m in values) {
      if (m != desconocida && m.codigo == v) {
        return m;
      }
    }
    return desconocida;
  }
}
