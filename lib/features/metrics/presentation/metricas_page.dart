import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/network/mensaje_error_gateway.dart';
import 'package:mani/core/widgets/mani_button.dart';
import 'package:mani/features/services/quotes/presentation/cotizacion_page.dart'
    show formatearPesos;
import 'package:mani/features/tariffs/presentation/reporte_fuera_rango_page.dart'
    show fechaIso;

import '../data/metricas_datasource.dart';

class MetricasState extends Equatable {
  const MetricasState({
    required this.desde,
    required this.hasta,
    this.cargando = false,
    this.metricas,
    this.error,
  });

  final DateTime desde;
  final DateTime hasta;
  final bool cargando;
  final MetricasOperativas? metricas;
  final String? error;

  @override
  List<Object?> get props => [desde, hasta, cargando, metricas, error];
}

/// Métricas operativas del tenant (HU-M12-06 / SCRUM-900). Por omisión, el mes
/// en curso. Solo muestra lo que devuelve Core para el tenant de la sesión.
class MetricasCubit extends Cubit<MetricasState> {
  MetricasCubit(this._fuente, {DateTime? hoy})
    : super(
        MetricasState(
          desde: DateTime(
            (hoy ?? DateTime.now()).year,
            (hoy ?? DateTime.now()).month,
          ),
          hasta: hoy ?? DateTime.now(),
        ),
      );

  final FuenteMetricas _fuente;

  void periodo(DateTime desde, DateTime hasta) =>
      emit(MetricasState(desde: desde, hasta: hasta, metricas: state.metricas));

  Future<void> consultar() async {
    emit(
      MetricasState(
        desde: state.desde,
        hasta: state.hasta,
        cargando: true,
        metricas: state.metricas,
      ),
    );
    try {
      final m = await _fuente.consultar(
        fechaIso(state.desde),
        fechaIso(state.hasta),
      );
      emit(MetricasState(desde: state.desde, hasta: state.hasta, metricas: m));
    } catch (e) {
      emit(
        MetricasState(
          desde: state.desde,
          hasta: state.hasta,
          error: mensajeErrorGateway(e),
        ),
      );
    }
  }
}

String _tasa(double? t) =>
    t == null ? '—' : '${(t * 100).toStringAsFixed(1)} %';

class MetricasPage extends StatelessWidget {
  const MetricasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MetricasCubit, MetricasState>(
      builder: (context, state) {
        final cubit = context.read<MetricasCubit>();
        final tema = Theme.of(context).textTheme;
        final m = state.metricas;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Métricas operativas', style: tema.headlineSmall),
                const SizedBox(height: 4),
                const Text(
                  'Indicadores de tu empresa en el periodo elegido (fechas de '
                  'Colombia, inclusive).',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('metricas-periodo'),
                      icon: const Icon(Icons.date_range),
                      label: Text(
                        '${fechaIso(state.desde)} a ${fechaIso(state.hasta)}',
                      ),
                      onPressed: () async {
                        final rango = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2024),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                          initialDateRange: DateTimeRange(
                            start: state.desde,
                            end: state.hasta,
                          ),
                        );
                        if (rango != null) {
                          cubit.periodo(rango.start, rango.end);
                        }
                      },
                    ),
                    ManiButton(
                      key: const Key('metricas-consultar'),
                      etiqueta: 'Consultar',
                      icono: Icons.search,
                      cargando: state.cargando,
                      onPressed: state.cargando ? null : cubit.consultar,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (state.error != null)
                  Card(
                    key: const Key('metricas-error'),
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(state.error!),
                    ),
                  )
                else if (m != null) ...[
                  if (m.solicitudesCreadas == 0 && m.cotizacionesEmitidas == 0)
                    const Card(
                      key: Key('metricas-sin-datos'),
                      child: ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('No hubo actividad en el periodo'),
                      ),
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _Indicador(
                        'metrica-solicitudes',
                        'Solicitudes creadas',
                        '${m.solicitudesCreadas}',
                      ),
                      _Indicador(
                        'metrica-finalizadas',
                        'Finalizadas',
                        '${m.finalizadas}',
                      ),
                      _Indicador(
                        'metrica-canceladas',
                        'Canceladas',
                        '${m.canceladas} (${_tasa(m.tasaCancelacion)})',
                      ),
                      _Indicador(
                        'metrica-cotizaciones',
                        'Cotizaciones emitidas',
                        '${m.cotizacionesEmitidas}',
                      ),
                      _Indicador(
                        'metrica-aceptacion',
                        'Aceptación de cotizaciones',
                        _tasa(m.tasaAceptacion),
                      ),
                      _Indicador(
                        'metrica-pagos',
                        'Pagos aprobados',
                        '${m.pagosAprobados} · ${formatearPesos(m.montoAprobado)}',
                      ),
                      _Indicador(
                        'metrica-calificacion',
                        'Calificación promedio',
                        m.calificacionPromedio == null
                            ? 'Sin calificaciones'
                            : '${m.calificacionPromedio!.toStringAsFixed(2)} (${m.calificaciones})',
                      ),
                      _Indicador(
                        'metrica-quejas',
                        'Quejas',
                        '${m.quejasRegistradas} · ${m.quejasAbiertas} abiertas',
                      ),
                      _Indicador(
                        'metrica-aliados',
                        'Aliados con servicios',
                        '${m.aliadosConServicios}',
                      ),
                    ],
                  ),
                  if (m.porEstado.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Solicitudes por estado', style: tema.titleMedium),
                    for (final e in m.porEstado.entries)
                      ListTile(
                        dense: true,
                        key: Key('metrica-estado-${e.key}'),
                        title: Text(e.key),
                        trailing: Text('${e.value}'),
                      ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Indicador extends StatelessWidget {
  const _Indicador(this.clave, this.etiqueta, this.valor);

  final String clave;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return SizedBox(
      width: 260,
      child: Card(
        key: Key(clave),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(etiqueta, style: tema.bodySmall),
              const SizedBox(height: 4),
              Text(valor, style: tema.titleLarge),
            ],
          ),
        ),
      ),
    );
  }
}
