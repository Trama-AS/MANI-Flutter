import 'package:equatable/equatable.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';

import '../domain/calificacion_cierre_modelos.dart';
import 'calificacion_cierre_datasource.dart';

/// Tipo de cobro de la penalización por cancelación tardía (SCRUM-878).
enum TipoCobroPenalizacion {
  montoFijo('MONTO_FIJO', 'Monto fijo'),
  porcentaje('PORCENTAJE', 'Porcentaje de la cotización');

  const TipoCobroPenalizacion(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;

  static TipoCobroPenalizacion desde(String? v) =>
      v == 'PORCENTAJE' ? porcentaje : montoFijo;
}

/// Política de cancelación tardía del tenant (SCRUM-878). Sin política
/// configurada, Core responde la de por omisión con `activa: false`: no se
/// cobra penalización.
class PoliticaCancelacion extends Equatable {
  const PoliticaCancelacion({
    required this.activa,
    required this.ventanaGratuitaMinutos,
    required this.tipoCobro,
    required this.valor,
    this.configurada = false,
  });

  factory PoliticaCancelacion.fromJson(Map<String, dynamic> json) =>
      PoliticaCancelacion(
        activa: json['activa'] == true,
        ventanaGratuitaMinutos:
            (json['ventanaGratuitaMinutos'] as num?)?.toInt() ?? 15,
        tipoCobro: TipoCobroPenalizacion.desde(json['tipoCobro'] as String?),
        valor: (json['valor'] as num?)?.toDouble() ?? 0,
        configurada: json['configurada'] == true,
      );

  final bool activa;
  final int ventanaGratuitaMinutos;
  final TipoCobroPenalizacion tipoCobro;
  final double valor;
  final bool configurada;

  /// Mismas reglas que Core (MANI-PEN-422); `null` si es válida.
  String? get error {
    if (ventanaGratuitaMinutos < 0 || ventanaGratuitaMinutos > 1440) {
      return 'La ventana gratuita va de 0 a 1440 minutos.';
    }
    if (valor < 0) return 'El valor no puede ser negativo.';
    if (tipoCobro == TipoCobroPenalizacion.porcentaje && valor > 100) {
      return 'El porcentaje no puede superar 100.';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'activa': activa,
    'ventanaGratuitaMinutos': ventanaGratuitaMinutos,
    'tipoCobro': tipoCobro.valor,
    'valor': valor,
  };

  PoliticaCancelacion copiar({
    bool? activa,
    int? ventanaGratuitaMinutos,
    TipoCobroPenalizacion? tipoCobro,
    double? valor,
  }) => PoliticaCancelacion(
    activa: activa ?? this.activa,
    ventanaGratuitaMinutos:
        ventanaGratuitaMinutos ?? this.ventanaGratuitaMinutos,
    tipoCobro: tipoCobro ?? this.tipoCobro,
    valor: valor ?? this.valor,
    configurada: configurada,
  );

  @override
  List<Object?> get props => [
    activa,
    ventanaGratuitaMinutos,
    tipoCobro,
    valor,
    configurada,
  ];
}

/// Fuente de la política de cancelación del tenant (SCRUM-878).
abstract interface class FuentePoliticaCancelacion {
  Future<PoliticaCancelacion> obtener();

  Future<PoliticaCancelacion> guardar(PoliticaCancelacion politica);
}

/// Política por el Gateway a Core (`/api/v1/core/tenants/me/politica-cancelacion`).
/// El tenant sale del JWT; solo el admin_tenant guarda (Core responde 403 al
/// resto).
class GatewayFuentePoliticaCancelacion implements FuentePoliticaCancelacion {
  GatewayFuentePoliticaCancelacion(this._gateway);

  static const ruta = '/api/v1/core/tenants/me/politica-cancelacion';

  final GatewayClient _gateway;

  @override
  Future<PoliticaCancelacion> obtener() => _llamar(() => _gateway.get(ruta));

  @override
  Future<PoliticaCancelacion> guardar(PoliticaCancelacion politica) =>
      _llamar(() => _gateway.put(ruta, politica.toJson()));

  static Future<PoliticaCancelacion> _llamar(
    Future<Map<String, dynamic>> Function() op,
  ) async {
    try {
      final res = await op();
      final p = res['politica'];
      if (p is! Map) {
        throw const ModuloM08Failure(
          ModuloM08ErrorTipo.desconocido,
          'Respuesta de Core sin "politica"',
        );
      }
      return PoliticaCancelacion.fromJson(Map<String, dynamic>.from(p));
    } on GatewayException catch (e) {
      throw GatewayFuenteModuloM08.mapearGateway(e);
    }
  }
}
