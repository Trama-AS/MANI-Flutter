import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/platform/guardador_archivo.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_button.dart';
import 'package:mani/core/widgets/mani_card.dart';
import 'package:mani/features/services/quotes/presentation/cotizacion_page.dart'
    show formatearPesos;

import '../data/cobros_datasource.dart';
import '../domain/pago.dart';
import 'pago_cubit.dart';
import 'retencion_pago_card.dart';

/// Pago de una cotización aceptada en el sandbox (SCRUM-1432, HU-M11-01).
///
/// Es un simulador: no cobra dinero real ni pide datos de tarjeta. La persona
/// solo elige el desenlace que quiere probar. El monto lo calcula Core a partir
/// de la cotización; [total], si llega, es solo una ayuda para mostrar antes.
class PagoSandboxPage extends StatelessWidget {
  const PagoSandboxPage({
    super.key,
    this.total,
    this.cobros,
    this.guardador,
  });

  /// Guarda el comprobante en el dispositivo; si no llega, no hay botón de descarga (SCRUM-890).
  final GuardadorArchivo? guardador;

  /// Fuente de la retención en garantía; si no llega, no se muestra (SCRUM-891).
  final FuenteCobros? cobros;

  /// Total de la cotización que se está pagando, para mostrarlo antes de pagar.
  final double? total;

  /// Texto fijo del aviso de sandbox, visible antes y después de pagar.
  static const avisoSandbox =
      'SANDBOX · PAGO SIMULADO. No se cobra dinero real ni se piden datos de '
      'tarjeta.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Pago en sandbox'),
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.dark,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: AppTheme.dark, width: 2)),
      ),
      body: BlocBuilder<PagoCubit, PagoState>(
        builder: (context, state) {
          final cubit = context.read<PagoCubit>();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                children: [
                  ManiCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _AvisoSandbox(),
                        const SizedBox(height: 20),
                        if (total != null) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF9C3),
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusXl,
                              ),
                              border: Border.all(
                                color: AppTheme.dark,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total cotización:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  'Total de tu cotización: ${formatearPesos(total!)}',
                                  key: const Key('total-cotizacion'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    color: AppTheme.dark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        DropdownButtonFormField<EscenarioPago>(
                          key: const Key('escenario-pago'),
                          initialValue: state.escenario,
                          decoration: InputDecoration(
                            labelText: 'Resultado que quieres simular',
                            labelStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.dark,
                            ),
                            filled: true,
                            fillColor: AppTheme.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusMd,
                              ),
                              borderSide: const BorderSide(
                                color: AppTheme.dark,
                                width: 2,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusMd,
                              ),
                              borderSide: const BorderSide(
                                color: AppTheme.dark,
                                width: 2,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusMd,
                              ),
                              borderSide: const BorderSide(
                                color: AppTheme.dark,
                                width: 2.5,
                              ),
                            ),
                          ),
                          items: [
                            for (final e in EscenarioPago.values)
                              DropdownMenuItem(
                                value: e,
                                child: Text(
                                  e.etiqueta,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                          onChanged: state.pagando
                              ? null
                              : (e) {
                                  if (e != null) cubit.elegirEscenario(e);
                                },
                        ),
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 180,
                              maxWidth: 260,
                            ),
                            child: ManiButton(
                              key: const Key('btn-pagar-sandbox'),
                              etiqueta: 'Pagar (simulado)',
                              icono: Icons.payments_outlined,
                              expandir: true,
                              cargando: state.pagando,
                              onPressed: state.pagando ? null : cubit.pagar,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: 16),
                    _ErrorPago(error: state.error!),
                  ],
                  if (state.pago != null) ...[
                    const SizedBox(height: 16),
                    _ResultadoPago(pago: state.pago!),
                    if (state.comprobante != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _Comprobante(
                          comprobante: state.comprobante!,
                          guardador: guardador,
                        ),
                      ),
                    if (cobros != null && state.pago!.aprobado)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: RetencionPagoCard(
                          fuente: cobros!,
                          pagoId: state.pago!.id,
                        ),
                      ),
                    if (state.falloComprobante)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'El pago se aprobó, pero no pudimos traer el comprobante. '
                          'Vuelve a abrir esta pantalla en unos minutos.',
                          key: Key('sin-comprobante'),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AvisoSandbox extends StatelessWidget {
  const _AvisoSandbox();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('aviso-sandbox'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF9C3),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.dark, width: 1.5),
      ),
      child: const Row(
        children: [
          Icon(Icons.science_outlined, color: AppTheme.dark),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              PagoSandboxPage.avisoSandbox,
              style: TextStyle(
                color: AppTheme.dark,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPago extends StatelessWidget {
  const _ErrorPago({required this.error});

  final PagoFailure error;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('error-pago'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.error, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error.mensajeUsuario,
            style: const TextStyle(
              color: AppTheme.error,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (error.correlationId != null) ...[
            const SizedBox(height: 4),
            Text(
              'Código de seguimiento: ${error.correlationId}',
              key: const Key('correlacion-pago'),
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultadoPago extends StatelessWidget {
  const _ResultadoPago({required this.pago});

  final Pago pago;

  @override
  Widget build(BuildContext context) {
    return ManiCard(
      key: const Key('resultado-pago'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: pago.estado == EstadoPago.aprobado
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEF9C3),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(color: AppTheme.dark, width: 1.5),
                ),
                child: Text(
                  'Pago ${pago.etiquetaEstado.toLowerCase()}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              const Spacer(),
              if (pago.simulado)
                Container(
                  key: const Key('pago-simulado'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: AppTheme.dark, width: 1),
                  ),
                  child: const Text(
                    'PAGO SIMULADO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Monto: ${formatearPesos(pago.monto)} ${pago.moneda}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Referencia: ${pago.referenciaProveedor}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          if (pago.motivo != null && pago.motivo!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Motivo: ${pago.motivo}'),
          ],
          if (pago.estado == EstadoPago.pendiente) ...[
            const SizedBox(height: 8),
            const Text(
              'El proveedor simulado lo dejó pendiente; puedes volver a '
              'intentarlo con otro resultado.',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _Comprobante extends StatelessWidget {
  const _Comprobante({required this.comprobante, this.guardador});

  final ComprobantePago comprobante;
  final GuardadorArchivo? guardador;

  Future<void> _descargar(BuildContext context) async {
    final mensajero = ScaffoldMessenger.of(context);
    try {
      final guardado = await guardador!.guardar(
        nombre: comprobante.nombreArchivo,
        bytes: Uint8List.fromList(utf8.encode(comprobante.comoTexto())),
        tipoMime: 'text/plain',
      );
      if (guardado) {
        mensajero.showSnackBar(
          const SnackBar(content: Text('Comprobante guardado.')),
        );
      }
    } catch (_) {
      mensajero.showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos guardar el comprobante. Inténtalo de nuevo.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ManiCard(
      key: const Key('comprobante-pago'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: AppTheme.dark),
              const SizedBox(width: 8),
              Text(
                'Comprobante ${comprobante.numero}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Monto: ${formatearPesos(comprobante.monto)} ${comprobante.moneda}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (comprobante.fecha != null) ...[
            const SizedBox(height: 4),
            Text(
              'Fecha: ${comprobante.fecha}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
          if (guardador != null) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: ManiButton(
                key: const Key('btn-descargar-comprobante'),
                onPressed: () => _descargar(context),
                icono: Icons.download_outlined,
                etiqueta: 'Descargar comprobante',
                variante: ManiButtonVariante.secundario,
              ),
            ),
          ],
          if (comprobante.leyenda != null) ...[
            const SizedBox(height: 10),
            Text(
              comprobante.leyenda!,
              key: const Key('leyenda-comprobante'),
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
