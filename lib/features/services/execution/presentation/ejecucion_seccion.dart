import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_button.dart';
import 'package:mani/core/widgets/mani_card.dart';
import 'package:mani/features/services/tracking/presentation/mis_solicitudes_page.dart'
    show formatearFecha;

import '../data/ejecucion_datasource.dart';
import 'ejecucion_cubit.dart';

/// Sección «Ejecución» de la pantalla del servicio (US-04.3.1 / SCRUM-868).
///
/// El aliado marca el inicio y el fin; el cliente ve las dos horas. Las horas
/// son del servidor y la regla de cuándo se puede iniciar (cotización aceptada
/// o tarifa estándar) la aplica Core: si no se cumple, se muestra su mensaje.
class EjecucionSeccion extends StatelessWidget {
  const EjecucionSeccion({super.key, required this.esAliado});

  final bool esAliado;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<EjecucionCubit, EjecucionState>(
      listenWhen: (a, b) => b.aviso != null && a.aviso != b.aviso,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(state.aviso!),
              backgroundColor: state.avisoEsError
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          );
      },
      builder: (context, state) {
        final e = state.ejecucion;
        return ManiCard(
          key: const Key('seccion-ejecucion'),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(color: AppTheme.dark, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.play_circle_outline,
                      size: 18,
                      color: AppTheme.dark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Ejecución',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.dark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (state.cargando && e == null)
                const LinearProgressIndicator(color: AppTheme.dark)
              else if (state.error != null && e == null)
                Row(
                  children: [
                    Expanded(child: Text(state.error!)),
                    TextButton(
                      onPressed: context.read<EjecucionCubit>().cargar,
                      child: const Text('Reintentar'),
                    ),
                  ],
                )
              else if (e != null) ...[
                _Marca('Inicio', e.inicio, key: const Key('marca-inicio')),
                _Marca('Fin', e.fin, key: const Key('marca-fin')),
                if (esAliado) _Acciones(ejecucion: e, enviando: state.enviando),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Marca extends StatelessWidget {
  const _Marca(this.etiqueta, this.marca, {super.key});

  final String etiqueta;
  final MarcaEjecucion? marca;

  @override
  Widget build(BuildContext context) {
    final m = marca;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        m == null
            ? '$etiqueta: pendiente'
            : '$etiqueta: ${formatearFecha(m.registradoEn)}'
                  '${(m.observacion ?? '').isEmpty ? '' : ' · ${m.observacion}'}',
      ),
    );
  }
}

class _Acciones extends StatelessWidget {
  const _Acciones({required this.ejecucion, required this.enviando});

  final Ejecucion ejecucion;
  final bool enviando;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<EjecucionCubit>();
    if (ejecucion.finalizada) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Servicio finalizado.'),
      );
    }
    final hito = ejecucion.enEjecucion
        ? HitoEjecucion.fin
        : HitoEjecucion.inicio;
    if (hito == HitoEjecucion.inicio && !ejecucion.puedeIniciar) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Podrás iniciar cuando el cliente acepte la cotización.'),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
          child: ManiButton(
            key: Key('btn-${hito.ruta}-servicio'),
            etiqueta: hito == HitoEjecucion.inicio
                ? 'Iniciar servicio'
                : 'Finalizar servicio',
            icono: hito == HitoEjecucion.inicio
                ? Icons.play_arrow_rounded
                : Icons.flag_rounded,
            expandir: true,
            cargando: enviando,
            onPressed: enviando ? null : () => cubit.marcar(hito),
          ),
        ),
      ),
    );
  }
}
