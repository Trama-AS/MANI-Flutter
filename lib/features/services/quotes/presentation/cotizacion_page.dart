import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mani/core/widgets/mani_button.dart';

import '../domain/cotizacion.dart';
import 'cotizacion_cubit.dart';

/// Importe de la cotización: no negativo, hasta diez enteros y dos decimales,
/// el mismo formato que valida Core (DECIMAL(12,2)).
final _importeRe = RegExp(r'^\d{1,10}([.,]\d{1,2})?$');

/// `1234567.5` → `$ 1.234.567,50`.
String formatearPesos(double valor) {
  final partes = valor.toStringAsFixed(2).split('.');
  final enteros = partes[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return '\$ $enteros,${partes[1]}';
}

/// Cotización de una solicitud (US-04.2.1 y US-04.2.3).
///
/// - Aliado asignado ([esAliado]): emite la cotización con mano de obra y
///   materiales separados. Puede emitir otra versión cuando el cliente pide
///   un ajuste (SCRUM-865).
/// - Cliente dueño: ve la versión vigente y la acepta, la rechaza con motivo o
///   pide un ajuste con comentario (SCRUM-867).
///
/// El total y la versión los calcula Core; la app solo muestra el total
/// mientras se escribe, como ayuda.
class CotizacionPage extends StatelessWidget {
  const CotizacionPage({
    super.key,
    required this.esAliado,
    this.encabezado,
    this.pie,
    this.alRefrescar,
    this.alPagar,
  });

  final bool esAliado;

  /// Sección bajo el título (p. ej. la tarifa de referencia, SCRUM-886).
  final Widget? encabezado;

  /// Sección que va al final de la pantalla (p. ej. la ejecución, SCRUM-868).
  final Widget? pie;

  /// Se llama además de recargar la cotización al deslizar hacia abajo.
  final Future<void> Function()? alRefrescar;

  /// Abre el pago en el sandbox de una cotización aceptada (SCRUM-1432). Solo
  /// el cliente lo recibe; sin él no se ofrece el botón.
  final void Function(String cotizacionId, double total)? alPagar;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CotizacionCubit, CotizacionState>(
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
        final cubit = context.read<CotizacionCubit>();
        return RefreshIndicator(
          onRefresh: () async {
            await Future.wait([cubit.cargar(), ?alRefrescar?.call()]);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                esAliado ? 'Cotizar el servicio' : 'Cotización del servicio',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              if (encabezado != null) ...[
                encabezado!,
                const SizedBox(height: 12),
              ],
              if (state.cargando && state.cotizaciones.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (state.error != null)
                _Error(mensaje: state.error!, onReintentar: cubit.cargar)
              else ...[
                if (state.vigente != null)
                  _TarjetaCotizacion(state.vigente!, vigente: true),
                if (esAliado)
                  _SeccionAliado(state: state)
                else
                  _SeccionCliente(state: state, alPagar: alPagar),
                if (state.cotizaciones.length > 1) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Versiones anteriores',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final c in state.cotizaciones.skip(1))
                    _TarjetaCotizacion(c, vigente: false),
                ],
              ],
              if (pie != null) ...[const SizedBox(height: 16), pie!],
            ],
          ),
        );
      },
    );
  }
}

class _TarjetaCotizacion extends StatelessWidget {
  const _TarjetaCotizacion(this.c, {required this.vigente});

  final Cotizacion c;
  final bool vigente;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Card(
      key: Key('cotizacion-v${c.version}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Versión ${c.version}',
                    style: vigente ? tema.titleMedium : tema.titleSmall,
                  ),
                ),
                Chip(label: Text(c.etiquetaEstado)),
              ],
            ),
            const SizedBox(height: 8),
            _Renglon('Mano de obra', formatearPesos(c.valorManoObra)),
            _Renglon('Materiales', formatearPesos(c.valorMateriales)),
            const Divider(),
            _Renglon('Total', formatearPesos(c.total), negrita: true),
          ],
        ),
      ),
    );
  }
}

class _Renglon extends StatelessWidget {
  const _Renglon(this.etiqueta, this.valor, {this.negrita = false});

  final String etiqueta;
  final String valor;
  final bool negrita;

  @override
  Widget build(BuildContext context) {
    final estilo = negrita
        ? const TextStyle(fontWeight: FontWeight.w800)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(etiqueta, style: estilo)),
          Text(valor, style: estilo),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ aliado

class _SeccionAliado extends StatelessWidget {
  const _SeccionAliado({required this.state});

  final CotizacionState state;

  @override
  Widget build(BuildContext context) {
    final vigente = state.vigente;
    // Core admite una versión nueva cuando no hay ninguna pendiente y el
    // cliente no aceptó ni rechazó (SCRUM-865, MANI-COT-409P y 409E).
    if (vigente == null ||
        vigente.estado == EstadoCotizacion.ajusteSolicitado) {
      return _FormularioCotizacion(
        enviando: state.enviando,
        titulo: vigente == null
            ? 'Envía tu cotización al cliente'
            : 'El cliente pidió un ajuste: envía la versión ${vigente.version + 1}',
      );
    }
    final texto = switch (vigente.estado) {
      EstadoCotizacion.pendiente =>
        'Esperando la respuesta del cliente. Te avisaremos en tu bandeja.',
      EstadoCotizacion.aceptada => 'El cliente aceptó la cotización.',
      EstadoCotizacion.rechazada => 'El cliente rechazó la cotización.',
      _ => 'Esta cotización ya no admite cambios.',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(texto, key: const Key('estado-cotizacion-aliado')),
    );
  }
}

class _FormularioCotizacion extends StatefulWidget {
  const _FormularioCotizacion({required this.enviando, required this.titulo});

  final bool enviando;
  final String titulo;

  @override
  State<_FormularioCotizacion> createState() => _FormularioCotizacionState();
}

class _FormularioCotizacionState extends State<_FormularioCotizacion> {
  final _form = GlobalKey<FormState>();
  final _manoObra = TextEditingController();
  final _materiales = TextEditingController(text: '0');

  @override
  void dispose() {
    _manoObra.dispose();
    _materiales.dispose();
    super.dispose();
  }

  static String _normalizado(String v) => v.trim().replaceAll(',', '.');

  static double? _valor(String v) =>
      _importeRe.hasMatch(v.trim()) ? double.parse(_normalizado(v)) : null;

  String? _validar(String? v) {
    if (v == null || v.trim().isEmpty) return 'Obligatorio';
    if (!_importeRe.hasMatch(v.trim())) {
      return 'Valor no negativo con máximo dos decimales';
    }
    return null;
  }

  void _enviar() {
    if (!_form.currentState!.validate()) return;
    final total =
        (_valor(_manoObra.text) ?? 0) + (_valor(_materiales.text) ?? 0);
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El total debe ser mayor que cero')),
      );
      return;
    }
    context.read<CotizacionCubit>().emitir(
      valorManoObra: _normalizado(_manoObra.text),
      valorMateriales: _normalizado(_materiales.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formato = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(widget.titulo, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('campo-mano-obra'),
            controller: _manoObra,
            decoration: const InputDecoration(
              labelText: 'Mano de obra',
              prefixText: '\$ ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: formato,
            validator: _validar,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('campo-materiales'),
            controller: _materiales,
            decoration: const InputDecoration(
              labelText: 'Materiales',
              prefixText: '\$ ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: formato,
            validator: _validar,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            'Total: ${formatearPesos((_valor(_manoObra.text) ?? 0) + (_valor(_materiales.text) ?? 0))}',
            key: const Key('total-calculado'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ManiButton(
            key: const Key('btn-enviar-cotizacion'),
            etiqueta: widget.enviando ? 'Enviando…' : 'Enviar cotización',
            icono: Icons.send_rounded,
            expandir: true,
            cargando: widget.enviando,
            onPressed: widget.enviando ? null : _enviar,
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- cliente

class _SeccionCliente extends StatelessWidget {
  const _SeccionCliente({required this.state, this.alPagar});

  final CotizacionState state;
  final void Function(String cotizacionId, double total)? alPagar;

  @override
  Widget build(BuildContext context) {
    final vigente = state.vigente;
    if (vigente == null) {
      return const Text(
        'El aliado aún no ha enviado la cotización. Desliza hacia abajo para '
        'actualizar.',
        key: Key('sin-cotizacion'),
      );
    }
    if (!vigente.pendiente) {
      final texto = switch (vigente.estado) {
        EstadoCotizacion.ajusteSolicitado =>
          'Pediste un ajuste. El aliado enviará una nueva versión.',
        EstadoCotizacion.aceptada => 'Aceptaste esta cotización.',
        EstadoCotizacion.rechazada => 'Rechazaste esta cotización.',
        _ => 'Esta cotización ya no admite respuesta.',
      };
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(texto, key: const Key('estado-cotizacion-cliente')),
            if (vigente.estado == EstadoCotizacion.aceptada &&
                alPagar != null) ...[
              const SizedBox(height: 8),
              ManiButton(
                key: const Key('btn-pagar-cotizacion'),
                etiqueta: 'Pagar (sandbox)',
                icono: Icons.payments_outlined,
                expandir: true,
                onPressed: () => alPagar!(vigente.id, vigente.total),
              ),
            ],
          ],
        ),
      );
    }
    final cubit = context.read<CotizacionCubit>();
    final habilitado = !state.enviando;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        ManiButton(
          key: const Key('btn-aceptar-cotizacion'),
          etiqueta: 'Aceptar cotización',
          icono: Icons.check_rounded,
          expandir: true,
          cargando: state.enviando,
          onPressed: habilitado
              ? () => cubit.responder(DecisionCotizacion.aceptar)
              : null,
        ),
        const SizedBox(height: 8),
        ManiButton(
          key: const Key('btn-ajustar-cotizacion'),
          etiqueta: 'Pedir ajuste',
          icono: Icons.edit_note_rounded,
          variante: ManiButtonVariante.secundario,
          expandir: true,
          onPressed: habilitado
              ? () => _pedirTexto(
                  context,
                  titulo: 'Pedir ajuste',
                  etiqueta: '¿Qué debe cambiar el aliado?',
                  minimo: 3,
                  decision: DecisionCotizacion.ajustar,
                )
              : null,
        ),
        const SizedBox(height: 8),
        ManiButton(
          key: const Key('btn-rechazar-cotizacion'),
          etiqueta: 'Rechazar',
          icono: Icons.close_rounded,
          variante: ManiButtonVariante.secundario,
          expandir: true,
          onPressed: habilitado
              ? () => _pedirTexto(
                  context,
                  titulo: 'Rechazar cotización',
                  etiqueta: 'Motivo del rechazo',
                  minimo: 5,
                  decision: DecisionCotizacion.rechazar,
                )
              : null,
        ),
      ],
    );
  }

  Future<void> _pedirTexto(
    BuildContext context, {
    required String titulo,
    required String etiqueta,
    required int minimo,
    required DecisionCotizacion decision,
  }) async {
    final cubit = context.read<CotizacionCubit>();
    final texto = await showDialog<String>(
      context: context,
      builder: (_) =>
          _DialogoTexto(titulo: titulo, etiqueta: etiqueta, minimo: minimo),
    );
    if (texto != null) await cubit.responder(decision, texto: texto);
  }
}

class _DialogoTexto extends StatefulWidget {
  const _DialogoTexto({
    required this.titulo,
    required this.etiqueta,
    required this.minimo,
  });

  final String titulo;
  final String etiqueta;
  final int minimo;

  @override
  State<_DialogoTexto> createState() => _DialogoTextoState();
}

class _DialogoTextoState extends State<_DialogoTexto> {
  final _texto = TextEditingController();

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valido = _texto.text.trim().length >= widget.minimo;
    return AlertDialog(
      title: Text(widget.titulo),
      content: TextField(
        key: const Key('campo-texto-decision'),
        controller: _texto,
        maxLength: 500,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: widget.etiqueta,
          helperText: 'Mínimo ${widget.minimo} caracteres',
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('btn-confirmar-decision'),
          onPressed: valido
              ? () => Navigator.of(context).pop(_texto.text.trim())
              : null,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final Future<void> Function() onReintentar;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('error-cotizacion'),
      child: ListTile(
        leading: const Icon(Icons.error_outline),
        title: Text(mensaje),
        trailing: TextButton(
          onPressed: onReintentar,
          child: const Text('Reintentar'),
        ),
      ),
    );
  }
}
