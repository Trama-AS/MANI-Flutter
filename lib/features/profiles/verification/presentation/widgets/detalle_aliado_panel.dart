import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_button.dart';
import 'package:mani/core/widgets/mani_card.dart';

import '../../domain/entities/solicitud_aliado.dart';
import '../bloc/bandeja_verificacion_cubit.dart';
import '../utils/formato_fecha.dart';
import 'aliado_avatar.dart';
import 'dialogos_verificacion.dart';
import 'documento_kyc_tile.dart';
import 'estado_verificacion_badge.dart';

/// Perfil completo del aliado candidato con sus documentos y las acciones
/// Aprobar / Rechazar. Se usa como panel derecho (escritorio) y como cuerpo
/// de la página de detalle (móvil).
class DetalleAliadoPanel extends StatelessWidget {
  const DetalleAliadoPanel({
    super.key,
    required this.aliadoId,
    this.onCerrar,
    this.onResuelto,
  });

  final String aliadoId;

  /// Si se provee, muestra un botón para cerrar el panel.
  final VoidCallback? onCerrar;

  /// Se invoca tras aprobar o rechazar con éxito.
  final VoidCallback? onResuelto;

  Future<void> _aprobar(BuildContext context, SolicitudAliado aliado) async {
    final cubit = context.read<BandejaVerificacionCubit>();
    if (!await confirmarAprobacion(context, aliado)) return;
    if (await cubit.aprobar(aliado.id)) onResuelto?.call();
  }

  Future<void> _rechazar(BuildContext context, SolicitudAliado aliado) async {
    final cubit = context.read<BandejaVerificacionCubit>();
    final motivo = await pedirMotivoRechazo(context, aliado);
    if (motivo == null) return;
    if (await cubit.rechazar(aliado.id, motivo)) onResuelto?.call();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BandejaVerificacionCubit, BandejaVerificacionState>(
      builder: (context, state) {
        final aliado = state.porId(aliadoId);
        if (aliado == null) {
          return const Center(
            child: Text('Este aliado ya no está en la bandeja.'),
          );
        }
        final procesando = state.procesandoId == aliadoId;
        final bloqueado = state.procesando;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.cargandoDetalleId == aliadoId)
              const LinearProgressIndicator(
                minHeight: 3,
                color: AppTheme.dark,
                backgroundColor: AppTheme.primary,
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _Encabezado(aliado: aliado, onCerrar: onCerrar),
                  const SizedBox(height: 20),
                  _Seccion(
                    titulo: 'Datos del registro',
                    icono: Icons.person_search_outlined,
                    child: _DatosRegistro(aliado: aliado),
                  ),
                  const SizedBox(height: 20),
                  _Seccion(
                    titulo: 'Documentos KYC (${aliado.documentos.length})',
                    icono: Icons.folder_open_rounded,
                    child: aliado.tieneDocumentos
                        ? Column(
                            children: [
                              for (final d in aliado.documentos)
                                DocumentoKycTile(
                                  documento: d,
                                  onVer: () => context
                                      .read<BandejaVerificacionCubit>()
                                      .abrirDocumento(d),
                                ),
                            ],
                          )
                        : const _Aviso(
                            icono: Icons.report_gmailerrorred,
                            color: AppTheme.error,
                            texto:
                                'Este aliado no adjuntó documentos. No puedes aprobarlo; '
                                'recházalo indicando qué debe cargar.',
                          ),
                  ),
                  const SizedBox(height: 20),
                  if (aliado.estaPendiente)
                    const _Aviso(
                      icono: Icons.lightbulb_outline_rounded,
                      color: Color(0xFFB45309),
                      texto:
                          'Antes de decidir, verifica que los documentos sean legibles, '
                          'estén vigentes y que el nombre coincida con el registro.',
                    )
                  else
                    _Resultado(aliado: aliado),
                ],
              ),
            ),
            if (aliado.estaPendiente)
              _BarraAcciones(
                procesando: procesando,
                puedeAprobar: aliado.tieneDocumentos && !bloqueado,
                puedeRechazar: !bloqueado,
                onAprobar: () => _aprobar(context, aliado),
                onRechazar: () => _rechazar(context, aliado),
              ),
          ],
        );
      },
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.aliado, this.onCerrar});

  final SolicitudAliado aliado;
  final VoidCallback? onCerrar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return ManiCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AliadoAvatar(aliado: aliado, tamano: 64),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  aliado.nombre,
                  style: tema.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  aliado.email,
                  style: tema.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                EstadoVerificacionBadge(estado: aliado.estado),
              ],
            ),
          ),
          if (onCerrar != null)
            IconButton(
              tooltip: 'Cerrar detalle',
              onPressed: onCerrar,
              icon: const Icon(Icons.close_rounded, color: AppTheme.dark),
            ),
        ],
      ),
    );
  }
}

class _DatosRegistro extends StatelessWidget {
  const _DatosRegistro({required this.aliado});

  final SolicitudAliado aliado;

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    return Column(
      children: [
        _Dato(etiqueta: 'Tipo de aliado', valor: aliado.tipo.etiqueta),
        _Dato(
          etiqueta: 'Fecha de registro',
          valor:
              '${fechaCorta(aliado.fechaRegistro)} · ${haceCuanto(aliado.fechaRegistro, ahora)}',
        ),
        _Dato(
          etiqueta: 'Especialidades',
          child: aliado.categorias.isEmpty
              ? const Text(
                  'Sin especialidad declarada',
                  style: TextStyle(color: AppTheme.textSecondary),
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in aliado.categorias)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.dark, width: 1.5),
                        ),
                        child: Text(
                          c,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, this.valor, this.child});

  final String etiqueta;
  final String? valor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiqueta.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          child ??
              Text(
                valor ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.dark,
                ),
              ),
        ],
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({
    required this.titulo,
    required this.icono,
    required this.child,
  });

  final String titulo;
  final IconData icono;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icono, size: 18, color: AppTheme.dark),
            const SizedBox(width: 8),
            Text(
              titulo,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.color, required this.texto});

  final IconData icono;
  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Resultado extends StatelessWidget {
  const _Resultado({required this.aliado});

  final SolicitudAliado aliado;

  @override
  Widget build(BuildContext context) {
    final estado = aliado.estado;
    final fecha = aliado.fechaVerificacion;
    final aprobado = estado == EstadoVerificacion.aprobado;
    return Container(
      key: const ValueKey('resultado-verificacion'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: estado.fondo,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.dark, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(estado.icono, color: estado.acento),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    aprobado ? 'Aliado aprobado' : 'Aliado rechazado',
                    if (fecha != null) 'el ${fechaCorta(fecha)}',
                  ].join(' '),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: estado.acento,
                  ),
                ),
              ),
            ],
          ),
          if (!aprobado && (aliado.motivoRechazo ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Motivo enviado al aliado:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(aliado.motivoRechazo!),
          ],
        ],
      ),
    );
  }
}

class _BarraAcciones extends StatelessWidget {
  const _BarraAcciones({
    required this.procesando,
    required this.puedeAprobar,
    required this.puedeRechazar,
    required this.onAprobar,
    required this.onRechazar,
  });

  final bool procesando;
  final bool puedeAprobar;
  final bool puedeRechazar;
  final VoidCallback onAprobar;
  final VoidCallback onRechazar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.dark, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: procesando
            ? const SizedBox(
                height: 48,
                child: Row(
                  key: ValueKey('guardando-decision'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppTheme.dark,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Guardando decisión…',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              )
            : Row(
                children: [
                  Expanded(
                    child: ManiButton(
                      key: const ValueKey('btn-rechazar'),
                      etiqueta: 'Rechazar',
                      icono: Icons.close_rounded,
                      variante: ManiButtonVariante.peligro,
                      expandir: true,
                      onPressed: puedeRechazar ? onRechazar : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ManiButton(
                      key: const ValueKey('btn-aprobar'),
                      etiqueta: 'Aprobar',
                      icono: Icons.check_rounded,
                      expandir: true,
                      onPressed: puedeAprobar ? onAprobar : null,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
