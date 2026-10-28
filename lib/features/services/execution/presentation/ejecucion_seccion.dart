import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/widgets/mani_button.dart';
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
        return Card(
          key: const Key('seccion-ejecucion'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ejecución',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (state.cargando && e == null)
                  const LinearProgressIndicator()
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
                  if (esAliado)
                    _Acciones(ejecucion: e, enviando: state.enviando),
                ],
              ],
            ),
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
      padding: const EdgeInsets.only(top: 12),
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
    );
  }
}
