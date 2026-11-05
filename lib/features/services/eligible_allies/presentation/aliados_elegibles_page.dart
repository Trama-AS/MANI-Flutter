import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_card.dart';

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
              color: AppTheme.dark,
              backgroundColor: AppTheme.primary,
              onRefresh: cubit.cargar,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                children: [
                  const Text(
                    'Aliados para tu solicitud',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.dark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FiltroTipo(
                    seleccionado: state.tipo,
                    onCambiar: state.cargando ? null : cubit.filtrar,
                  ),
                  const SizedBox(height: 16),
                  if (state.error != null)
                    _Error(mensaje: state.error!, onReintentar: cubit.cargar),
                  if (state.cargando && lista == null)
                    const Padding(
                      key: Key('elegibles-cargando'),
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(color: AppTheme.dark),
                      ),
                    )
                  else if (lista != null) ...[
                    _AvisoOrden(lista),
                    const SizedBox(height: 12),
                    if (lista.aliados.isEmpty)
                      _Vacio(filtrado: state.tipo != null)
                    else ...[
                      for (final (i, a) in lista.aliados.indexed) ...[
                        _TarjetaAliado(
                          a,
                          puesto: lista.ordenAplicado
                              ? (a.posicion ?? i + 1)
                              : null,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (lista.total > lista.aliados.length)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            'Mostrando ${lista.aliados.length} de ${lista.total} aliados.',
                            key: const Key('elegibles-parcial'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
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
    Widget chip(TipoAliado? tipo, String etiqueta) {
      final activo = seleccionado == tipo;
      return FilterChip(
        key: Key('elegibles-tipo-${tipo?.valor ?? 'TODOS'}'),
        label: Text(
          etiqueta,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.dark,
            fontSize: 13,
          ),
        ),
        selected: activo,
        selectedColor: AppTheme.primary,
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          side: const BorderSide(color: AppTheme.dark, width: 1.5),
        ),
        onSelected: onCambiar == null ? null : (_) => onCambiar!(tipo),
      );
    }

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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: aplicado ? const Color(0xFFEFF6FF) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.dark, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            aplicado ? Icons.sort : Icons.info_outline,
            size: 18,
            color: AppTheme.dark,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              aplicado
                  ? 'Ordenados por las reglas de tu empresa: primero los más adecuados.'
                  : 'Orden no disponible: los aliados no están ordenados por recomendación.',
              key: Key(aplicado ? 'elegibles-orden' : 'elegibles-sin-orden'),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppTheme.dark,
              ),
            ),
          ),
        ],
      ),
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
    return ManiCard(
      key: Key('elegible-${aliado.id}'),
      padding: const EdgeInsets.all(16),
      sombra: AppTheme.hardShadowSm,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: puesto != null ? AppTheme.primary : AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.dark, width: 2),
            ),
            child: puesto != null
                ? Text(
                    '$puesto',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: AppTheme.dark,
                    ),
                  )
                : const Icon(Icons.person_outline, color: AppTheme.dark),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        aliado.nombre.isEmpty ? 'Aliado' : aliado.nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: Border.all(color: AppTheme.dark, width: 1),
                      ),
                      child: const Text(
                        'Verificado',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  aliado.etiquetaTipo,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  aliado.textoCalificacionAgregada,
                  key: Key('elegible-calificacion-${aliado.id}'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.dark,
                  ),
                ),
                if (puesto != null && aliado.razones.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final r in aliado.razones)
                    Text(
                      '• $r',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
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
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w600,
        ),
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
    return Container(
      key: const Key('elegibles-error'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.error, width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(
                color: AppTheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            key: const Key('elegibles-reintentar'),
            onPressed: onReintentar,
            child: const Text(
              'Reintentar',
              style: TextStyle(
                color: AppTheme.error,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
