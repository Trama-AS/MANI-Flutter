import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/network/mensaje_error_gateway.dart';
import 'package:mani/core/widgets/mani_button.dart';

import '../domain/queja.dart';
import 'quejas_cubit.dart';

String _fecha(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${dos(l.month)}-${dos(l.day)} ${dos(l.hour)}:${dos(l.minute)}';
}

/// Quejas del cliente (HU-M12-01 / SCRUM-895) o del tenant (HU-M12-02 /
/// SCRUM-896), según [QuejasCubit.esAdmin]. El administrador cambia el estado
/// con las transiciones válidas; cerrar exige la respuesta al cliente.
class QuejasPage extends StatelessWidget {
  const QuejasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<QuejasCubit, QuejasState>(
      listenWhen: (a, b) => b.aviso != null && a.aviso != b.aviso,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              key: const Key('quejas-aviso'),
              content: Text(state.aviso!),
              backgroundColor: state.avisoEsError
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          );
      },
      builder: (context, state) {
        final cubit = context.read<QuejasCubit>();
        final tema = Theme.of(context).textTheme;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: RefreshIndicator(
              onRefresh: cubit.cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    cubit.esAdmin ? 'Quejas del tenant' : 'Mis quejas',
                    style: tema.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cubit.esAdmin
                        ? 'Atiende las quejas de los clientes y cambia su estado. '
                              'Cada cambio queda registrado con tu usuario.'
                        : 'Quejas que presentaste sobre tus servicios. Para '
                              'presentar una nueva, ve a Mis solicitudes.',
                  ),
                  if (cubit.esAdmin) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          key: const Key('filtro-todas'),
                          label: const Text('Todas'),
                          selected: state.filtro == null,
                          onSelected: (_) => cubit.filtrar(null),
                        ),
                        for (final e in EstadoQueja.values)
                          ChoiceChip(
                            key: Key('filtro-${e.valor}'),
                            label: Text(e.etiqueta),
                            selected: state.filtro == e,
                            onSelected: (_) => cubit.filtrar(e),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (state.cargando && state.quejas.isEmpty)
                    const Center(child: CircularProgressIndicator())
                  else if (state.error != null)
                    Card(
                      key: const Key('quejas-error'),
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: Text(state.error!),
                        trailing: TextButton(
                          onPressed: cubit.cargar,
                          child: const Text('Reintentar'),
                        ),
                      ),
                    )
                  else if (state.quejas.isEmpty)
                    const Card(
                      key: Key('quejas-vacio'),
                      child: ListTile(
                        leading: Icon(Icons.inbox_outlined),
                        title: Text('No hay quejas'),
                      ),
                    )
                  else
                    for (final q in state.quejas)
                      _TarjetaQueja(
                        queja: q,
                        esAdmin: cubit.esAdmin,
                        actualizando: state.actualizandoId == q.id,
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

class _TarjetaQueja extends StatelessWidget {
  const _TarjetaQueja({
    required this.queja,
    required this.esAdmin,
    required this.actualizando,
  });

  final Queja queja;
  final bool esAdmin;
  final bool actualizando;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final cubit = context.read<QuejasCubit>();
    return Card(
      key: Key('queja-${queja.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${queja.etiquetaMotivo} · ${queja.categoria}',
                    style: tema.titleMedium,
                  ),
                ),
                Chip(
                  key: Key('queja-estado-${queja.id}'),
                  label: Text(queja.estado.etiqueta),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(queja.descripcion),
            const SizedBox(height: 4),
            Text(
              [
                'Presentada ${_fecha(queja.creadaEn)}',
                if (esAdmin && queja.clienteEmail != null) queja.clienteEmail!,
              ].join(' · '),
              style: tema.bodySmall,
            ),
            if (queja.respuesta != null) ...[
              const SizedBox(height: 8),
              Text(
                'Respuesta: ${queja.respuesta}',
                key: Key('queja-respuesta-${queja.id}'),
              ),
            ],
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton.icon(
                  key: Key('queja-historial-${queja.id}'),
                  icon: const Icon(Icons.history),
                  label: const Text('Historial'),
                  onPressed: () => _verHistorial(context, cubit, queja),
                ),
                if (esAdmin && actualizando)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (esAdmin)
                  for (final siguiente in queja.estado.siguientes)
                    TextButton(
                      key: Key('queja-${siguiente.valor}-${queja.id}'),
                      onPressed: () =>
                          _cambiarEstado(context, cubit, queja, siguiente),
                      child: Text(switch (siguiente) {
                        EstadoQueja.enRevision => 'Pasar a revisión',
                        EstadoQueja.resuelta => 'Resolver',
                        EstadoQueja.rechazada => 'Rechazar',
                        EstadoQueja.abierta => 'Reabrir',
                      }),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _cambiarEstado(
  BuildContext context,
  QuejasCubit cubit,
  Queja queja,
  EstadoQueja estado,
) async {
  String? nota;
  if (estado.esFinal) {
    nota = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoRespuesta(estado: estado),
    );
    if (nota == null) return;
  }
  await cubit.cambiarEstado(queja, estado, nota: nota);
}

Future<void> _verHistorial(
  BuildContext context,
  QuejasCubit cubit,
  Queja queja,
) => showDialog<void>(
  context: context,
  builder: (_) => AlertDialog(
    title: const Text('Historial de la queja'),
    content: SizedBox(
      width: 460,
      child: FutureBuilder<List<TransicionQueja>>(
        future: cubit.historial(queja.id),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError) return Text(mensajeErrorGateway(snap.error!));
          return ListView(
            shrinkWrap: true,
            children: [
              for (final (i, h) in snap.data!.indexed)
                ListTile(
                  key: Key('queja-transicion-$i'),
                  dense: true,
                  title: Text(
                    h.estadoAnterior == null
                        ? 'Presentada (${h.estadoNuevo.etiqueta})'
                        : '${h.estadoAnterior!.etiqueta} → ${h.estadoNuevo.etiqueta}',
                  ),
                  subtitle: Text(
                    [
                      _fecha(h.fecha),
                      h.actorRol == 'ADMIN' ? 'Administrador' : 'Cliente',
                      if (h.nota != null) h.nota!,
                    ].join(' · '),
                  ),
                ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cerrar'),
      ),
    ],
  ),
);

/// Respuesta al cliente al cerrar una queja: entre 5 y 1000 caracteres.
class _DialogoRespuesta extends StatefulWidget {
  const _DialogoRespuesta({required this.estado});

  final EstadoQueja estado;

  @override
  State<_DialogoRespuesta> createState() => _DialogoRespuestaState();
}

class _DialogoRespuestaState extends State<_DialogoRespuesta> {
  final _nota = TextEditingController();

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  bool get _valida {
    final n = _nota.text.trim().runes.length;
    return n >= 5 && n <= 1000;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.estado == EstadoQueja.resuelta
            ? 'Resolver queja'
            : 'Rechazar queja',
      ),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const Key('queja-nota'),
          controller: _nota,
          maxLines: 3,
          maxLength: 1000,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Respuesta para el cliente',
            helperText: 'Mínimo 5 caracteres',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ManiButton(
          key: const Key('queja-confirmar'),
          etiqueta: 'Confirmar',
          onPressed: _valida
              ? () => Navigator.of(context).pop(_nota.text.trim())
              : null,
        ),
      ],
    );
  }
}
