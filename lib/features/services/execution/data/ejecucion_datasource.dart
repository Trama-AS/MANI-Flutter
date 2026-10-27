import 'package:equatable/equatable.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/services/quotes/data/cotizaciones_datasource.dart';
import 'package:mani/features/services/quotes/domain/cotizacion.dart';

/// Una marca de la ejecución con la hora que puso el servidor.
class MarcaEjecucion extends Equatable {
  const MarcaEjecucion({required this.registradoEn, this.observacion});

  static MarcaEjecucion? desde(Object? json) {
    if (json is! Map) return null;
    final fecha = DateTime.tryParse((json['registradoEn'] as String?) ?? '');
    if (fecha == null) return null;
    return MarcaEjecucion(
      registradoEn: fecha.toLocal(),
      observacion: json['observacion'] as String?,
    );
  }

  final DateTime registradoEn;
  final String? observacion;

  @override
  List<Object?> get props => [registradoEn, observacion];
}

/// Inicio y fin del servicio (US-04.3.1 / SCRUM-868).
class Ejecucion extends Equatable {
  const Ejecucion({required this.estadoCrudo, this.inicio, this.fin});

  factory Ejecucion.fromJson(Map<String, dynamic> json) => Ejecucion(
    estadoCrudo: (json['estado'] as String?) ?? '',
    inicio: MarcaEjecucion.desde(json['inicio']),
    fin: MarcaEjecucion.desde(json['fin']),
  );

  final String estadoCrudo;
  final MarcaEjecucion? inicio;
  final MarcaEjecucion? fin;

  String get _estado => estadoCrudo.trim().toUpperCase();

  /// Core decide si se puede iniciar (cotización aceptada o tarifa estándar);
  /// la app solo ofrece el botón en los estados donde tiene sentido.
  bool get puedeIniciar => _estado == 'ACEPTADA' || _estado == 'ASIGNADA';
  bool get enEjecucion => _estado == 'EN_EJECUCION';
  bool get finalizada => _estado == 'FINALIZADA';

  @override
  List<Object?> get props => [estadoCrudo, inicio, fin];
}

enum HitoEjecucion {
  inicio('iniciar'),
  fin('finalizar');

  const HitoEjecucion(this.ruta);

  final String ruta;
}

abstract interface class FuenteEjecucion {
  Future<Ejecucion> consultar(String solicitudId);

  Future<void> marcar(
    String solicitudId,
    HitoEjecucion hito, {
    String? observacion,
  });
}

/// Ejecución por el Gateway a Core. La app no envía fechas: la hora es la del
/// servidor (CONS-24). Los errores se traducen igual que los de la cotización.
class GatewayFuenteEjecucion implements FuenteEjecucion {
  GatewayFuenteEjecucion(this._gateway);

  static String rutaConsulta(String solicitudId) =>
      '/api/v1/core/solicitudes/$solicitudId/ejecucion';
  static String rutaMarca(String solicitudId, HitoEjecucion hito) =>
      '/api/v1/core/solicitudes/$solicitudId/${hito.ruta}';

  final GatewayClient _gateway;

  @override
  Future<Ejecucion> consultar(String solicitudId) async {
    try {
      final res = await _gateway.get(rutaConsulta(solicitudId));
      final e = res['ejecucion'];
      if (e is! Map) {
        throw const CotizacionFailure(
          CotizacionErrorTipo.desconocido,
          'Respuesta de Core sin "ejecucion"',
        );
      }
      return Ejecucion.fromJson(Map<String, dynamic>.from(e));
    } on GatewayException catch (e) {
      throw GatewayFuenteCotizaciones.mapearGateway(e);
    }
  }

  @override
  Future<void> marcar(
    String solicitudId,
    HitoEjecucion hito, {
    String? observacion,
  }) async {
    try {
      await _gateway.postJson(rutaMarca(solicitudId, hito), {
        if (observacion != null && observacion.trim().isNotEmpty)
          'observacion': observacion.trim(),
      });
    } on GatewayException catch (e) {
      throw GatewayFuenteCotizaciones.mapearGateway(e);
    }
  }
}
