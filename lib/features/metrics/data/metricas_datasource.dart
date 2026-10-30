import 'package:equatable/equatable.dart';
import 'package:mani/core/network/gateway_client.dart';

int _entero(Object? v) => v is num ? v.toInt() : 0;
double? _decimal(Object? v) => v is num ? v.toDouble() : null;

/// Métricas operativas del tenant en un periodo (HU-M12-06 / SCRUM-900). Los
/// valores son los de Core tal cual: un periodo sin datos trae ceros y las
/// tasas en `null` (C2), nunca valores de demostración.
class MetricasOperativas extends Equatable {
  const MetricasOperativas({
    required this.solicitudesCreadas,
    required this.porEstado,
    required this.finalizadas,
    required this.canceladas,
    required this.cotizacionesEmitidas,
    required this.cotizacionesAceptadas,
    required this.pagosAprobados,
    required this.montoAprobado,
    required this.calificaciones,
    required this.quejasRegistradas,
    required this.quejasAbiertas,
    required this.quejasCerradas,
    required this.aliadosConServicios,
    this.tasaCancelacion,
    this.tasaAceptacion,
    this.calificacionPromedio,
  });

  factory MetricasOperativas.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> m(String k) =>
        Map<String, dynamic>.from((json[k] as Map?) ?? const {});
    final sol = m('solicitudes'), cot = m('cotizaciones'), pag = m('pagos');
    final cal = m('calificaciones'), qja = m('quejas');
    return MetricasOperativas(
      solicitudesCreadas: _entero(sol['creadas']),
      porEstado: {
        for (final e in ((sol['porEstado'] as Map?) ?? const {}).entries)
          '${e.key}': _entero(e.value),
      },
      finalizadas: _entero(sol['finalizadas']),
      canceladas: _entero(sol['canceladas']),
      tasaCancelacion: _decimal(sol['tasaCancelacion']),
      cotizacionesEmitidas: _entero(cot['emitidas']),
      cotizacionesAceptadas: _entero(cot['aceptadas']),
      tasaAceptacion: _decimal(cot['tasaAceptacion']),
      pagosAprobados: _entero(pag['aprobados']),
      montoAprobado: _decimal(pag['montoAprobado']) ?? 0,
      calificaciones: _entero(cal['total']),
      calificacionPromedio: _decimal(cal['promedio']),
      quejasRegistradas: _entero(qja['registradas']),
      quejasAbiertas: _entero(qja['abiertas']),
      quejasCerradas: _entero(qja['cerradas']),
      aliadosConServicios: _entero(json['aliadosConServicios']),
    );
  }

  final int solicitudesCreadas;
  final Map<String, int> porEstado;
  final int finalizadas;
  final int canceladas;
  final double? tasaCancelacion;
  final int cotizacionesEmitidas;
  final int cotizacionesAceptadas;
  final double? tasaAceptacion;
  final int pagosAprobados;
  final double montoAprobado;
  final int calificaciones;
  final double? calificacionPromedio;
  final int quejasRegistradas;
  final int quejasAbiertas;
  final int quejasCerradas;
  final int aliadosConServicios;

  @override
  List<Object?> get props => [
    solicitudesCreadas,
    porEstado,
    finalizadas,
    canceladas,
    tasaCancelacion,
    cotizacionesEmitidas,
    cotizacionesAceptadas,
    tasaAceptacion,
    pagosAprobados,
    montoAprobado,
    calificaciones,
    calificacionPromedio,
    quejasRegistradas,
    quejasAbiertas,
    quejasCerradas,
    aliadosConServicios,
  ];
}

abstract interface class FuenteMetricas {
  /// [desde] y [hasta] en `YYYY-MM-DD`, ambos inclusive.
  Future<MetricasOperativas> consultar(String desde, String hasta);
}

/// Métricas por el Gateway a Core (SCRUM-900). El tenant sale del JWT.
class GatewayFuenteMetricas implements FuenteMetricas {
  GatewayFuenteMetricas(this._gateway);

  static const ruta = '/api/v1/core/metricas/operativas';

  final GatewayClient _gateway;

  @override
  Future<MetricasOperativas> consultar(String desde, String hasta) async =>
      MetricasOperativas.fromJson(
        await _gateway.get(
          ruta,
          queryParameters: {'desde': desde, 'hasta': hasta},
        ),
      );
}
