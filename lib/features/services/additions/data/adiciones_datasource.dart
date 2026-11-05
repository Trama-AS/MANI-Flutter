import 'package:equatable/equatable.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/services/quotes/data/cotizaciones_datasource.dart';
import 'package:mani/features/services/quotes/domain/cotizacion.dart';

double _numero(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

enum EstadoAdicion { pendiente, aceptada, rechazada, desconocido }

EstadoAdicion _estado(Object? v) => switch ('$v'.trim().toUpperCase()) {
  'PENDIENTE' => EstadoAdicion.pendiente,
  'ACEPTADA' => EstadoAdicion.aceptada,
  'RECHAZADA' => EstadoAdicion.rechazada,
  _ => EstadoAdicion.desconocido,
};

/// Adición por imprevisto (US-04.3.5 / SCRUM-872). Core calcula el total.
class Adicion extends Equatable {
  const Adicion({
    required this.id,
    required this.motivo,
    required this.valorManoObra,
    required this.valorMateriales,
    required this.total,
    required this.estado,
    this.tiempoAdicionalMinutos,
    this.comentarioCliente,
  });

  factory Adicion.fromJson(Map<String, dynamic> json) => Adicion(
    id: '${json['id']}',
    motivo: (json['motivo'] as String?) ?? '',
    valorManoObra: _numero(json['valorManoObra']),
    valorMateriales: _numero(json['valorMateriales']),
    total: _numero(json['total']),
    estado: _estado(json['estado']),
    tiempoAdicionalMinutos: (json['tiempoAdicionalMinutos'] as num?)?.toInt(),
    comentarioCliente: json['comentarioCliente'] as String?,
  );

  final String id;
  final String motivo;
  final double valorManoObra;
  final double valorMateriales;
  final double total;
  final EstadoAdicion estado;
  final int? tiempoAdicionalMinutos;
  final String? comentarioCliente;

  bool get pendiente => estado == EstadoAdicion.pendiente;

  @override
  List<Object?> get props => [
    id,
    motivo,
    valorManoObra,
    valorMateriales,
    total,
    estado,
    tiempoAdicionalMinutos,
    comentarioCliente,
  ];
}

/// Total vigente del servicio: la cotización aceptada más las adiciones
/// aceptadas. Es el monto que cobra el pago (SCRUM-1432).
class ResumenAdiciones extends Equatable {
  const ResumenAdiciones({
    required this.totalCotizacion,
    required this.totalAdicionesAceptadas,
    required this.totalVigente,
    required this.disponibleParaAdiciones,
  });

  static ResumenAdiciones? desde(Object? json) {
    if (json is! Map) return null;
    return ResumenAdiciones(
      totalCotizacion: _numero(json['totalCotizacion']),
      totalAdicionesAceptadas: _numero(json['totalAdicionesAceptadas']),
      totalVigente: _numero(json['totalVigente']),
      disponibleParaAdiciones: _numero(json['disponibleParaAdiciones']),
    );
  }

  final double totalCotizacion;
  final double totalAdicionesAceptadas;
  final double totalVigente;
  final double disponibleParaAdiciones;

  @override
  List<Object?> get props => [
    totalCotizacion,
    totalAdicionesAceptadas,
    totalVigente,
    disponibleParaAdiciones,
  ];
}

class AdicionesServicio extends Equatable {
  const AdicionesServicio({required this.adiciones, this.resumen});

  final List<Adicion> adiciones;

  /// Null si la solicitud aún no tiene una cotización aceptada.
  final ResumenAdiciones? resumen;

  bool get hayPendiente => adiciones.any((a) => a.pendiente);

  @override
  List<Object?> get props => [adiciones, resumen];
}

enum DecisionAdicion {
  aceptar('aceptar'),
  rechazar('rechazar');

  const DecisionAdicion(this.ruta);

  /// Último segmento de `POST /adiciones/{id}/<ruta>`.
  final String ruta;
}

abstract interface class FuenteAdiciones {
  Future<AdicionesServicio> listar(String solicitudId);

  Future<void> solicitar(
    String solicitudId, {
    required String motivo,
    required String valorManoObra,
    required String valorMateriales,
    int? tiempoAdicionalMinutos,
  });

  Future<void> responder(
    String adicionId,
    DecisionAdicion decision, {
    String? comentario,
  });
}

/// Adiciones por el Gateway a Core. Los importes viajan como texto para que
/// Core valide exactamente lo que escribió el aliado (igual que la cotización),
/// y los errores se traducen con el mismo criterio.
class GatewayFuenteAdiciones implements FuenteAdiciones {
  GatewayFuenteAdiciones(this._gateway);

  static String rutaSolicitud(String solicitudId) =>
      '/api/v1/core/solicitudes/$solicitudId/adiciones';
  static String rutaDecision(String adicionId, DecisionAdicion decision) =>
      '/api/v1/core/adiciones/$adicionId/${decision.ruta}';

  final GatewayClient _gateway;

  @override
  Future<AdicionesServicio> listar(String solicitudId) async {
    try {
      final res = await _gateway.get(rutaSolicitud(solicitudId));
      final lista = res['adiciones'];
      if (lista is! List) {
        throw const CotizacionFailure(
          CotizacionErrorTipo.desconocido,
          'Respuesta de Core sin "adiciones"',
        );
      }
      return AdicionesServicio(
        adiciones: lista
            .whereType<Map>()
            .map((e) => Adicion.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        resumen: ResumenAdiciones.desde(res['resumen']),
      );
    } on GatewayException catch (e) {
      throw GatewayFuenteCotizaciones.mapearGateway(e);
    }
  }

  @override
  Future<void> solicitar(
    String solicitudId, {
    required String motivo,
    required String valorManoObra,
    required String valorMateriales,
    int? tiempoAdicionalMinutos,
  }) async {
    try {
      await _gateway.postJson(rutaSolicitud(solicitudId), {
        'motivo': motivo.trim(),
        'valorManoObra': valorManoObra,
        'valorMateriales': valorMateriales,
        'tiempoAdicionalMinutos': ?tiempoAdicionalMinutos,
      });
    } on GatewayException catch (e) {
      throw GatewayFuenteCotizaciones.mapearGateway(e);
    }
  }

  @override
  Future<void> responder(
    String adicionId,
    DecisionAdicion decision, {
    String? comentario,
  }) async {
    try {
      await _gateway.postJson(rutaDecision(adicionId, decision), {
        if (comentario != null && comentario.trim().isNotEmpty)
          'comentario': comentario.trim(),
      });
    } on GatewayException catch (e) {
      throw GatewayFuenteCotizaciones.mapearGateway(e);
    }
  }
}
