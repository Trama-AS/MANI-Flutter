import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/aliado_elegible.dart';
import 'aliados_elegibles_cubit.dart';

/// Aliados elegibles de la solicitud (SCRUM-1398, 1400 y 1401). Filtra por
/// tipo con chips y muestra la lista en el orden exacto que entrega
/// Dispatch. Si Rules no ordenó la lista, lo dice: «Orden no disponible».
class AliadosElegiblesPage extends StatelessWidget {
  const AliadosElegiblesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AliadosElegiblesCubit, AliadosElegiblesState>(
      builder: (context, state) {
        final cubit = context.read<AliadosElegiblesCubit>();
        final lista = state.lista;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: RefreshIndicator(
              onRefresh: cubit.cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Aliados para tu solicitud',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _FiltroTipo(
                    seleccionado: state.tipo,
                    onCambiar: state.cargando ? null : cubit.filtrar,
                  ),
                  const SizedBox(height: 12),
                  if (state.error != null)
                    _Error(mensaje: state.error!, onReintentar: cubit.cargar),
                  if (state.cargando && lista == null)
                    const Padding(
                      key: Key('elegibles-cargando'),
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (lista != null) ...[
                    _AvisoOrden(lista),
                    const SizedBox(height: 8),
                    if (lista.aliados.isEmpty)
                      _Vacio(filtrado: state.tipo != null)
                    else ...[
                      for (final (i, a) in lista.aliados.indexed)
                        _TarjetaAliado(
                          a,
                          puesto: lista.ordenAplicado
                              ? (a.posicion ?? i + 1)
                              : null,
                        ),
                      if (lista.total > lista.aliados.length)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            'Mostrando ${lista.aliados.length} de ${lista.total} aliados.',
                            key: const Key('elegibles-parcial'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FiltroTipo extends StatelessWidget {
  const _FiltroTipo({required this.seleccionado, required this.onCambiar});

  final TipoAliado? seleccionado;
  final ValueChanged<TipoAliado?>? onCambiar;

  @override
  Widget build(BuildContext context) {
    Widget chip(TipoAliado? tipo, String etiqueta) => ChoiceChip(
      key: Key('elegibles-tipo-${tipo?.valor ?? 'TODOS'}'),
      label: Text(etiqueta),
      selected: seleccionado == tipo,
      onSelected: onCambiar == null ? null : (_) => onCambiar!(tipo),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip(null, 'Todos'),
        for (final t in TipoAliado.values) chip(t, t.etiqueta),
      ],
    );
  }
}

/// Dice de dónde sale el orden. Sin ranking de Rules no se inventa uno.
class _AvisoOrden extends StatelessWidget {
  const _AvisoOrden(this.lista);

  final ListaElegibles lista;

  @override
  Widget build(BuildContext context) {
    final aplicado = lista.ordenAplicado;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(aplicado ? Icons.sort : Icons.info_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            aplicado
                ? 'Ordenados por las reglas de tu empresa: primero los más adecuados.'
                : 'Orden no disponible: los aliados no están ordenados por recomendación.',
            key: Key(aplicado ? 'elegibles-orden' : 'elegibles-sin-orden'),
          ),
        ),
      ],
    );
  }
}

class _TarjetaAliado extends StatelessWidget {
  const _TarjetaAliado(this.aliado, {this.puesto});

  final AliadoElegible aliado;

  /// Puesto en el ranking; `null` si no hay orden.
  final int? puesto;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Card(
      key: Key('elegible-${aliado.id}'),
      child: ListTile(
        leading: puesto == null
            ? const CircleAvatar(child: Icon(Icons.person_outline))
            : CircleAvatar(child: Text('$puesto')),
        title: Text(aliado.nombre.isEmpty ? 'Aliado' : aliado.nombre),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(aliado.etiquetaTipo),
            if (puesto != null)
              for (final r in aliado.razones)
                Text('• $r', style: tema.bodySmall),
          ],
        ),
        trailing: const Chip(label: Text('Verificado')),
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({required this.filtrado});

  final bool filtrado;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        filtrado
            ? 'No hay aliados de este tipo para tu solicitud. Prueba con otro filtro.'
            : 'Todavía no hay aliados disponibles para tu solicitud.',
        key: const Key('elegibles-vacio'),
        textAlign: TextAlign.center,
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
        key: const Key('elegibles-error'),
        leading: Icon(Icons.error_outline, color: colores.onErrorContainer),
        title: Text(mensaje),
        trailing: TextButton(
          key: const Key('elegibles-reintentar'),
          onPressed: onReintentar,
          child: const Text('Reintentar'),
        ),
      ),
    );
  }
}
