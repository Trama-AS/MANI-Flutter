import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/solicitud_seguimiento.dart';
import 'mis_solicitudes_cubit.dart';

/// Mis solicitudes (HU-M07-04 / SCRUM-871): estado vigente y zona declarada
/// de cada solicitud del cliente. No muestra la ubicación del aliado ni se
/// actualiza sola: el cliente consulta de nuevo con «Actualizar».
class MisSolicitudesPage extends StatelessWidget {
  const MisSolicitudesPage({
    super.key,
    this.onNuevaSolicitud,
    this.onVerCotizacion,
    this.onVerAliados,
    this.onPresentarQueja,
  });

  final VoidCallback? onNuevaSolicitud;

  /// Presenta una queja sobre el servicio (HU-M12-01 / SCRUM-895). Solo se
  /// ofrece cuando la solicitud ya tuvo aliado; Core vuelve a validarlo.
  final void Function(String solicitudId)? onPresentarQueja;

  /// Abre la cotización de la solicitud (SCRUM-867).
  final void Function(String solicitudId)? onVerCotizacion;

  /// Abre los aliados elegibles de una solicitud pendiente (SCRUM-1401).
  final void Function(String solicitudId)? onVerAliados;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MisSolicitudesCubit, MisSolicitudesState>(
      builder: (context, state) {
        final cubit = context.read<MisSolicitudesCubit>();
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: RefreshIndicator(
              onRefresh: cubit.cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Encabezado(state: state, onActualizar: cubit.cargar),
                  const SizedBox(height: 8),
                  const _AvisoZona(),
                  const SizedBox(height: 12),
                  if (state.error != null)
                    _Error(mensaje: state.error!, onReintentar: cubit.cargar),
                  if (state.cargando && state.solicitudes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (state.solicitudes.isEmpty && state.error == null)
                    _Vacio(onNuevaSolicitud: onNuevaSolicitud)
                  else
                    for (final s in state.solicitudes)
                      _TarjetaSolicitud(
                        s,
                        onVerCotizacion:
                            onVerCotizacion == null || !s.tieneCotizacion
                            ? null
                            : () => onVerCotizacion!(s.id),
                        onVerAliados:
                            onVerAliados == null ||
                                s.estado != EstadoSeguimiento.pendiente
                            ? null
                            : () => onVerAliados!(s.id),
                        onPresentarQueja:
                            onPresentarQueja == null ||
                                s.estado == EstadoSeguimiento.pendiente ||
                                s.estado == EstadoSeguimiento.otro
                            ? null
                            : () => onPresentarQueja!(s.id),
                        cancelando: state.cancelandoId == s.id,
                        onCancelar:
                            !s.puedeCancelar || state.cancelandoId != null
                            ? null
                            : () => _confirmarCancelacion(context, cubit, s),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// QAS-08: cancelar es irreversible, así que se confirma antes y se ofrece
/// dejar un motivo opcional (queda en la línea de tiempo del servicio).
Future<void> _confirmarCancelacion(
  BuildContext context,
  MisSolicitudesCubit cubit,
  SolicitudSeguimiento solicitud,
) async {
  final motivo = await showDialog<String>(
    context: context,
    builder: (_) => _DialogoCancelar(solicitud: solicitud),
  );
  if (motivo == null) return;
  final ok = await cubit.cancelar(solicitud.id, motivo: motivo);
  if (ok && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        key: Key('cancelacion-ok'),
        content: Text('Cancelaste la solicitud.'),
      ),
    );
  }
}

class _DialogoCancelar extends StatefulWidget {
  const _DialogoCancelar({required this.solicitud});

  final SolicitudSeguimiento solicitud;

  @override
  State<_DialogoCancelar> createState() => _DialogoCancelarState();
}

class _DialogoCancelarState extends State<_DialogoCancelar> {
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asignada = widget.solicitud.estado != EstadoSeguimiento.pendiente;
    return AlertDialog(
      key: const Key('dialogo-cancelar'),
      title: const Text('¿Cancelar la solicitud?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vas a cancelar «${widget.solicitud.categoria}». '
            'Esta acción no se puede deshacer.'
            '${asignada ? ' Le avisaremos al aliado asignado.' : ''}',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('cancelar-motivo'),
            controller: _motivo,
            maxLength: 200,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Motivo (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('cancelar-volver'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Volver'),
        ),
        FilledButton(
          key: const Key('cancelar-confirmar'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(_motivo.text.trim()),
          child: const Text('Sí, cancelar'),
        ),
      ],
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.state, required this.onActualizar});

  final MisSolicitudesState state;
  final Future<void> Function() onActualizar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final consultado = state.consultadoEn;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mis solicitudes', style: tema.titleLarge),
              if (consultado != null)
                Text(
                  'Consultado: ${formatearFecha(consultado)}',
                  key: const Key('seguimiento-consultado'),
                  style: tema.bodySmall,
                ),
            ],
          ),
        ),
        TextButton.icon(
          key: const Key('seguimiento-actualizar'),
          onPressed: state.cargando ? null : onActualizar,
          icon: const Icon(Icons.refresh),
          label: const Text('Actualizar'),
        ),
      ],
    );
  }
}

class _AvisoZona extends StatelessWidget {
  const _AvisoZona();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'La zona es la que indicaste al publicar la solicitud. '
            'No es la ubicación del aliado: MANI no rastrea su posición.',
            key: Key('seguimiento-aviso-zona'),
          ),
        ),
      ],
    );
  }
}

class _TarjetaSolicitud extends StatelessWidget {
  const _TarjetaSolicitud(
    this.solicitud, {
    this.onVerCotizacion,
    this.onVerAliados,
    this.onPresentarQueja,
    this.onCancelar,
    this.cancelando = false,
  });

  final SolicitudSeguimiento solicitud;
  final VoidCallback? onVerCotizacion;

  /// Solo para solicitudes que ya tuvieron aliado (SCRUM-895).
  final VoidCallback? onPresentarQueja;

  /// Solo para solicitudes pendientes (SCRUM-1401).
  final VoidCallback? onVerAliados;

  /// Cancela antes de la ejecución (SCRUM-877); `null` si no se puede.
  final VoidCallback? onCancelar;
  final bool cancelando;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final zona = solicitud.zonaCompleta;
    return Card(
      key: Key('seguimiento-${solicitud.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(solicitud.categoria, style: tema.titleMedium),
                ),
                Chip(label: Text(solicitud.etiquetaEstado)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              zona.isEmpty
                  ? 'Zona declarada: sin información'
                  : 'Zona declarada: $zona',
            ),
            Text(
              'Estado actualizado: ${formatearFecha(solicitud.actualizadaEn)}',
              style: tema.bodySmall,
            ),
            if (onVerCotizacion != null ||
                onVerAliados != null ||
                onPresentarQueja != null ||
                onCancelar != null ||
                cancelando)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  if (cancelando)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (onCancelar != null)
                    TextButton.icon(
                      key: Key('cancelar-solicitud-${solicitud.id}'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancelar solicitud'),
                      onPressed: onCancelar,
                    ),
                  if (onVerAliados != null)
                    TextButton.icon(
                      key: Key('ver-aliados-${solicitud.id}'),
                      icon: const Icon(Icons.groups_outlined),
                      label: const Text('Ver aliados'),
                      onPressed: onVerAliados,
                    ),
                  if (onPresentarQueja != null)
                    TextButton.icon(
                      key: Key('presentar-queja-${solicitud.id}'),
                      icon: const Icon(Icons.feedback_outlined),
                      label: const Text('Presentar queja'),
                      onPressed: onPresentarQueja,
                    ),
                  if (onVerCotizacion != null)
                    TextButton.icon(
                      key: Key('ver-cotizacion-${solicitud.id}'),
                      icon: const Icon(Icons.request_quote_outlined),
                      label: const Text('Ver cotización'),
                      onPressed: onVerCotizacion,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({this.onNuevaSolicitud});

  final VoidCallback? onNuevaSolicitud;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Text('Aún no has publicado solicitudes.'),
          if (onNuevaSolicitud != null) ...[
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('seguimiento-nueva'),
              onPressed: onNuevaSolicitud,
              child: const Text('Publicar una solicitud'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final Future<void> Function() onReintentar;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Card(
      color: colores.errorContainer,
      child: ListTile(
        key: const Key('seguimiento-error'),
        leading: Icon(Icons.error_outline, color: colores.onErrorContainer),
        title: Text(mensaje),
        trailing: TextButton(
          onPressed: onReintentar,
          child: const Text('Reintentar'),
        ),
      ),
    );
  }
}

const _meses = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// "26 oct 2026, 16:05" en hora local.
String formatearFecha(DateTime fecha) {
  final f = fecha.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${f.day} ${_meses[f.month - 1]} ${f.year}, ${dos(f.hour)}:${dos(f.minute)}';
}
