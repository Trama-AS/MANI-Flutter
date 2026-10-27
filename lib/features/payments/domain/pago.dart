import 'package:equatable/equatable.dart';

/// Desenlace que el sandbox puede simular (HU-M11-01). Los dos últimos no
/// producen ningún pago: son fallos del proveedor, no un rechazo.
enum EscenarioPago {
  aprobado('APROBADO', 'Pago aprobado'),
  rechazado('RECHAZADO', 'Pago rechazado'),
  pendiente('PENDIENTE', 'Pago pendiente'),
  timeout('TIMEOUT', 'El proveedor no responde (timeout)'),
  respuestaInvalida(
    'RESPUESTA_INVALIDA',
    'El proveedor responde algo inválido',
  );

  const EscenarioPago(this.valor, this.etiqueta);

  /// Texto que Core espera en `escenario`.
  final String valor;
  final String etiqueta;
}

enum EstadoPago {
  aprobado('Aprobado'),
  rechazado('Rechazado'),
  pendiente('Pendiente'),
  otro('');

  const EstadoPago(this.etiqueta);

  final String etiqueta;

  static EstadoPago desde(String valor) => switch (valor.trim().toUpperCase()) {
    'APROBADO' => aprobado,
    'RECHAZADO' => rechazado,
    'PENDIENTE' => pendiente,
    _ => otro,
  };
}

double _numero(Object? v) => switch (v) {
  num n => n.toDouble(),
  String s => double.tryParse(s) ?? 0,
  _ => 0,
};

/// Pago del cliente en el sandbox (SCRUM-1432). El monto, el estado y la marca
/// de simulado los decide Core; la app no los calcula.
class Pago extends Equatable {
  const Pago({
    required this.id,
    required this.cotizacionId,
    required this.monto,
    required this.moneda,
    required this.estadoCrudo,
    required this.proveedor,
    required this.simulado,
    required this.referenciaProveedor,
    this.motivo,
  });

  factory Pago.fromJson(Map<String, dynamic> json) => Pago(
    id: json['id'] as String,
    cotizacionId: (json['cotizacionId'] as String?) ?? '',
    monto: _numero(json['monto']),
    moneda: (json['moneda'] as String?) ?? 'COP',
    estadoCrudo: (json['estado'] as String?) ?? '',
    proveedor: (json['proveedor'] as String?) ?? '',
    // Ante la duda, un pago se presenta como simulado: es el único que existe.
    simulado: (json['simulado'] as bool?) ?? true,
    referenciaProveedor: (json['referenciaProveedor'] as String?) ?? '',
    motivo: json['motivo'] as String?,
  );

  final String id;
  final String cotizacionId;
  final double monto;
  final String moneda;
  final String estadoCrudo;
  final String proveedor;
  final bool simulado;
  final String referenciaProveedor;
  final String? motivo;

  EstadoPago get estado => EstadoPago.desde(estadoCrudo);

  String get etiquetaEstado =>
      estado == EstadoPago.otro ? estadoCrudo : estado.etiqueta;

  bool get aprobado => estado == EstadoPago.aprobado;

  @override
  List<Object?> get props => [
    id,
    cotizacionId,
    monto,
    moneda,
    estadoCrudo,
    proveedor,
    simulado,
    referenciaProveedor,
    motivo,
  ];
}

/// Comprobante de un pago aprobado. En el sandbox viene marcado como simulado,
/// con una leyenda que lo dice: nunca se muestra como un recibo real.
class ComprobantePago extends Equatable {
  const ComprobantePago({
    required this.numero,
    required this.simulado,
    required this.monto,
    required this.moneda,
    this.leyenda,
    this.fecha,
  });

  factory ComprobantePago.fromJson(Map<String, dynamic> json) =>
      ComprobantePago(
        numero: (json['numero'] as String?) ?? '',
        simulado: (json['simulado'] as bool?) ?? true,
        monto: _numero(json['monto']),
        moneda: (json['moneda'] as String?) ?? 'COP',
        leyenda: json['leyenda'] as String?,
        fecha: DateTime.tryParse((json['fecha'] as String?) ?? '')?.toLocal(),
      );

  final String numero;
  final bool simulado;
  final double monto;
  final String moneda;
  final String? leyenda;
  final DateTime? fecha;

  @override
  List<Object?> get props => [numero, simulado, monto, moneda, leyenda, fecha];
}

enum PagoErrorTipo {
  sinConexion,
  sinSesion,
  sinPermiso,
  noEncontrado,
  datosInvalidos,
  conflicto,
  proveedorSinRespuesta,
  servicioNoDisponible,
  desconocido,
}

/// Fallo de una operación de pago con el mensaje para el usuario.
///
/// [detalle] es el texto de Core cuando ayuda a actuar (400, 409 y los fallos
/// del proveedor, que dicen que no se cobró nada). [correlationId] deja
/// rastrear el intento en los logs del Gateway y de Core.
class PagoFailure extends Equatable implements Exception {
  const PagoFailure(this.tipo, {this.detalle, this.correlationId});

  final PagoErrorTipo tipo;
  final String? detalle;
  final String? correlationId;

  String get mensajeUsuario => switch (tipo) {
    PagoErrorTipo.sinConexion =>
      'Sin conexión. Revisa tu red e inténtalo de nuevo. Si ya enviaste el '
          'pago, consulta tu solicitud antes de repetirlo.',
    PagoErrorTipo.sinSesion => 'Tu sesión expiró. Inicia sesión de nuevo.',
    PagoErrorTipo.sinPermiso => 'Tu cuenta no puede pagar esta cotización.',
    PagoErrorTipo.noEncontrado => 'No encontramos este pago o cotización.',
    PagoErrorTipo.datosInvalidos => detalle ?? 'Revisa los datos del pago.',
    PagoErrorTipo.conflicto =>
      detalle ?? 'El estado de la cotización cambió. Actualiza para verlo.',
    PagoErrorTipo.proveedorSinRespuesta =>
      detalle ??
          'El proveedor de pagos no dio una respuesta válida. No se realizó '
              'ningún cobro; inténtalo de nuevo.',
    PagoErrorTipo.servicioNoDisponible =>
      'El servicio no está disponible. Inténtalo en unos minutos.',
    PagoErrorTipo.desconocido =>
      'No se pudo completar el pago. Inténtalo de nuevo.',
  };

  @override
  List<Object?> get props => [tipo, detalle, correlationId];
}
