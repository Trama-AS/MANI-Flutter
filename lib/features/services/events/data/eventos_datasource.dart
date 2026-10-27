import 'package:equatable/equatable.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/services/quotes/data/cotizaciones_datasource.dart';
import 'package:mani/features/services/quotes/domain/cotizacion.dart';
import 'package:mani/features/services/requests/domain/entities/foto_adjunta.dart';

/// Tipo de evento que el aliado registra durante la ejecución (SCRUM-869).
enum TipoEventoAliado {
  avance('AVANCE', 'Avance'),
  novedad('NOVEDAD', 'Novedad'),
  observacion('OBSERVACION', 'Observación');

  const TipoEventoAliado(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;
}

/// Un evento de la línea de tiempo del servicio. El autor y la hora los pone
/// Core; la app no envía fechas.
class EventoServicio extends Equatable {
  const EventoServicio({
    required this.id,
    required this.tipo,
    required this.registradoEn,
    required this.autorRol,
    this.descripcion,
    this.tieneEvidencia = false,
  });

  factory EventoServicio.fromJson(Map<String, dynamic> json) {
    final autor = json['autor'] is Map
        ? Map<String, dynamic>.from(json['autor'] as Map)
        : const <String, dynamic>{};
    return EventoServicio(
      id: json['id'] as String,
      tipo: (json['tipo'] as String?) ?? '',
      descripcion: json['descripcion'] as String?,
      registradoEn:
          DateTime.tryParse(
            (json['registradoEn'] as String?) ?? '',
          )?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      autorRol: (autor['rol'] as String?) ?? '',
      tieneEvidencia: json['tieneEvidencia'] == true,
    );
  }

  final String id;
  final String tipo;
  final String? descripcion;
  final DateTime registradoEn;
  final String autorRol;
  final bool tieneEvidencia;

  /// Texto del tipo; uno que la app no conoce se muestra tal cual.
  String get etiquetaTipo => switch (tipo) {
    'SOLICITUD_CREADA' => 'Solicitud creada',
    'COTIZACION_ENVIADA' => 'Cotización enviada',
    'COTIZACION_ACEPTADA' => 'Cotización aceptada',
    'COTIZACION_RECHAZADA' => 'Cotización rechazada',
    'AJUSTE_SOLICITADO' => 'Ajuste solicitado',
    'INICIO_EJECUCION' => 'Inicio del servicio',
    'FIN_EJECUCION' => 'Fin del servicio',
    'EJECUCION_AVANCE' => 'Avance',
    'EJECUCION_NOVEDAD' => 'Novedad',
    'EJECUCION_OBSERVACION' => 'Observación',
    _ => tipo,
  };

  @override
  List<Object?> get props => [
    id,
    tipo,
    descripcion,
    registradoEn,
    autorRol,
    tieneEvidencia,
  ];
}

abstract interface class FuenteEventos {
  Future<List<EventoServicio>> listar(String solicitudId);

  Future<EventoServicio> registrar(
    String solicitudId, {
    required TipoEventoAliado tipo,
    required String observacion,
    required String claveIdempotencia,
    FotoAdjunta? foto,
  });
}

/// Eventos del servicio por el Gateway a Core (US-04.3.2 / SCRUM-869). El
/// registro va en multipart con la foto opcional y la clave de idempotencia en
/// la cabecera, así el `GatewayClient` puede reintentar sin duplicar.
class GatewayFuenteEventos implements FuenteEventos {
  GatewayFuenteEventos(this._gateway);

  static String ruta(String solicitudId) =>
      '/api/v1/core/solicitudes/$solicitudId/eventos';

  final GatewayClient _gateway;

  @override
  Future<List<EventoServicio>> listar(String solicitudId) async {
    try {
      final res = await _gateway.get(ruta(solicitudId));
      final lista = res['eventos'];
      if (lista is! List) {
        throw const FormatException('Respuesta de Core sin "eventos"');
      }
      return lista
          .whereType<Map>()
          .map((e) => EventoServicio.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on GatewayException catch (e) {
      throw GatewayFuenteCotizaciones.mapearGateway(e);
    } on FormatException catch (e) {
      throw CotizacionFailure(CotizacionErrorTipo.desconocido, e.message);
    }
  }

  @override
  Future<EventoServicio> registrar(
    String solicitudId, {
    required TipoEventoAliado tipo,
    required String observacion,
    required String claveIdempotencia,
    FotoAdjunta? foto,
  }) async {
    try {
      final res = await _gateway.postMultipart(
        ruta(solicitudId),
        campos: {
          'tipo': tipo.valor,
          'observacion': observacion,
          'claveIdempotencia': claveIdempotencia,
        },
        archivos: [
          if (foto != null)
            ArchivoMultipart(
              campo: 'foto',
              nombre: 'evidencia.${foto.extension}',
              bytes: foto.bytes,
              tipoContenido: foto.mime,
            ),
        ],
        headers: {GatewayClient.headerIdempotencyKey: claveIdempotencia},
      );
      final e = res['evento'];
      if (e is! Map) {
        throw const FormatException('Respuesta de Core sin "evento"');
      }
      return EventoServicio.fromJson(Map<String, dynamic>.from(e));
    } on GatewayException catch (e) {
      throw GatewayFuenteCotizaciones.mapearGateway(e);
    } on FormatException catch (e) {
      throw CotizacionFailure(CotizacionErrorTipo.desconocido, e.message);
    }
  }
}
