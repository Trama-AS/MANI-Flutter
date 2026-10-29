import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/calificacion_cierre_modelos.dart';
import 'calificacion_cierre_cubit.dart';

/// Sección de calificación bidireccional (SCRUM-874 y SCRUM-875) y cierre
/// condicionado (SCRUM-1418).
class CalificacionCierreSeccion extends StatefulWidget {
  const CalificacionCierreSeccion({super.key, required this.esAliado});

  /// `false` cuando califica el cliente (SCRUM-874); `true` cuando califica el
  /// aliado (SCRUM-875).
  final bool esAliado;

  @override
  State<CalificacionCierreSeccion> createState() =>
      _CalificacionCierreSeccionState();
}

class _CalificacionCierreSeccionState extends State<CalificacionCierreSeccion> {
  int _puntaje = 0;
  final _comentarioCtrl = TextEditingController();

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalificacionCierreCubit, CalificacionCierreState>(
      builder: (context, state) {
        final cubit = context.read<CalificacionCierreCubit>();
        final resumen = state.resumen;
        final miCalificacion = widget.esAliado
            ? resumen?.aliadoACliente
            : resumen?.clienteAAliado;
        final otraCalificacion = widget.esAliado
            ? resumen?.clienteAAliado
            : resumen?.aliadoACliente;
        final cierre = resumen?.cierre;

        return Card(
          key: const Key('m08-calificacion-cierre-card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.esAliado
                      ? 'Calificar al cliente y estado de cierre'
                      : 'Calificar al aliado y estado de cierre',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (cierre != null)
                  Container(
                    key: const Key('m08-estado-cierre-banner'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cierre.cierreCompleto
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.amber.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          cierre.cierreCompleto
                              ? Icons.verified_outlined
                              : Icons.hourglass_bottom_outlined,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            cierre.etiquetaEstadoCierre,
                            key: const Key('m08-estado-cierre-texto'),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (state.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.error!,
                    key: const Key('m08-calificacion-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (state.mensajeExito != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.mensajeExito!,
                    key: const Key('m08-calificacion-exito'),
                  ),
                ],
                const SizedBox(height: 12),
                if (miCalificacion != null) ...[
                  Text(
                    'Tu calificación enviada: ★ ${miCalificacion.puntaje}/5',
                    key: const Key('m08-mi-calificacion-registrada'),
                  ),
                  if (miCalificacion.comentario != null &&
                      miCalificacion.comentario!.isNotEmpty)
                    Text('Comentario: ${miCalificacion.comentario}'),
                ] else ...[
                  const Text('Selecciona un puntaje de 1 a 5 estrellas:'),
                  Row(
                    children: [
                      for (var i = 1; i <= 5; i++)
                        IconButton(
                          key: Key('m08-estrella-$i'),
                          icon: Icon(
                            i <= _puntaje ? Icons.star : Icons.star_border,
                            color: Colors.amber.shade700,
                          ),
                          onPressed: state.enviando
                              ? null
                              : () => setState(() => _puntaje = i),
                        ),
                    ],
                  ),
                  TextField(
                    key: const Key('m08-comentario-input'),
                    controller: _comentarioCtrl,
                    maxLength: 500,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Comentario (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('m08-enviar-calificacion-btn'),
                    onPressed: state.enviando
                        ? null
                        : () => cubit.calificar(
                            puntaje: _puntaje,
                            comentario: _comentarioCtrl.text,
                          ),
                    child: const Text('Enviar calificación'),
                  ),
                ],
                if (otraCalificacion != null) ...[
                  const Divider(height: 24),
                  Text(
                    'Calificación recibida: ★ ${otraCalificacion.puntaje}/5',
                    key: const Key('m08-otra-calificacion-registrada'),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('m08-cerrar-solicitud-btn'),
                  onPressed: state.enviando ? null : cubit.cerrarSolicitud,
                  child: const Text('Verificar cierre definitivo'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pantalla de historial de servicios del cliente (SCRUM-879) o de trabajos
/// del aliado (SCRUM-880).
class HistorialServiciosPage extends StatelessWidget {
  const HistorialServiciosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HistorialServiciosCubit, HistorialServiciosState>(
      builder: (context, state) {
        final cubit = context.read<HistorialServiciosCubit>();
        final titulo = cubit.esAliado
            ? 'Historial de trabajos'
            : 'Historial de servicios';
        final textoVacio = cubit.esAliado
            ? 'Sin trabajos asignados en tu historial.'
            : 'Sin servicios registrados en tu historial.';

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  titulo,
                  key: const Key('m08-historial-titulo'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (state.error != null)
                  Text(
                    state.error!,
                    key: const Key('m08-historial-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (state.cargando && state.registros.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else if (state.registros.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      textoVacio,
                      key: const Key('m08-historial-vacio'),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final item in state.registros)
                    _TarjetaHistorialItem(item: item, esAliado: cubit.esAliado),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TarjetaHistorialItem extends StatelessWidget {
  const _TarjetaHistorialItem({required this.item, required this.esAliado});

  final RegistroHistorialServicio item;
  final bool esAliado;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('m08-historial-item-${item.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.categoria,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  key: Key('m08-historial-estado-${item.id}'),
                  label: Text(item.estado),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(item.descripcion),
            Text('Zona: ${item.zona} · Dirección: ${item.direccion}'),
            if (item.nombreContraparte != null)
              Text(
                esAliado
                    ? 'Cliente: ${item.nombreContraparte}'
                    : 'Aliado: ${item.nombreContraparte}',
              ),
            if (item.valorTotal != null)
              Text('Valor total: \$${item.valorTotal!.toStringAsFixed(0)}'),
            if (item.penalizacionAplicada)
              Text(
                'Penalización aplicada: \$${item.penalizacionMonto.toStringAsFixed(0)}',
                key: Key('m08-historial-penalizacion-${item.id}'),
              ),
            if (item.calificacionEmitida != null)
              Text(
                'Calificación emitida: ★ ${item.calificacionEmitida!.puntaje}/5',
              ),
            if (item.calificacionRecibida != null)
              Text(
                'Calificación recibida: ★ ${item.calificacionRecibida!.puntaje}/5',
              ),
          ],
        ),
      ),
    );
  }
}

/// Widget de vista previa de penalización por cancelación tardía (SCRUM-878).
class ResumenPenalizacionCancelacionBanner extends StatelessWidget {
  const ResumenPenalizacionCancelacionBanner({
    super.key,
    required this.preview,
  });

  final VistaPreviaPenalizacion preview;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('m08-penalizacion-preview-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: preview.aplicaPenalizacion
            ? Colors.orange.withValues(alpha: 0.16)
            : Colors.blueGrey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        preview.resumenUsuario,
        key: const Key('m08-penalizacion-preview-texto'),
      ),
    );
  }
}
