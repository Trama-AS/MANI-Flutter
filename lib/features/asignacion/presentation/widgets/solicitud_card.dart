import 'package:flutter/material.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_button.dart';
import 'package:mani/core/widgets/mani_card.dart';

import '../../domain/entities/modalidad_servicio.dart';
import '../../domain/entities/regla_sitio.dart';
import '../../domain/entities/solicitud_entity.dart';
import '../bloc/solicitudes_aliado_cubit.dart';
import '../utils/formato_solicitud.dart';

/// Tarjeta de una solicitud. Si está disponible muestra Rechazar / Aceptar;
/// si ya es del aliado muestra la dirección y cuándo la ganó.
class SolicitudCard extends StatelessWidget {
  const SolicitudCard({
    super.key,
    required this.solicitud,
    this.onAceptar,
    this.onRechazar,
    this.accionEnCurso,
    this.bloqueada = false,
    this.recienAsignada = false,
    this.ahora,
  });

  final SolicitudEntity solicitud;
  final VoidCallback? onAceptar;
  final VoidCallback? onRechazar;

  /// Acción que se está enviando para ESTA solicitud.
  final AccionSolicitud? accionEnCurso;

  /// Otra solicitud se está procesando: se deshabilitan las acciones.
  final bool bloqueada;
  final bool recienAsignada;
  final DateTime? ahora;

  /// A partir de estos minutos de espera la solicitud se marca como urgente.
  static const int minutosUrgencia = 30;

  @override
  Widget build(BuildContext context) {
    final s = solicitud;
    final hoy = ahora ?? DateTime.now();
    final urgente =
        s.estaDisponible && s.minutosEsperando(hoy) >= minutosUrgencia;

    return ManiCard(
      key: ValueKey('card-solicitud-${s.id}'),
      seleccionada: recienAsignada,
      sombra: AppTheme.hardShadowSm,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.esMia ? const Color(0xFFDCFCE7) : AppTheme.primary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                  border: Border.all(color: AppTheme.dark, width: 2),
                ),
                child: Icon(
                  s.esMia
                      ? Icons.assignment_turned_in_outlined
                      : Icons.home_repair_service_rounded,
                  color: AppTheme.dark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.categoria,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.dark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _Dato(
                      icono: Icons.place_outlined,
                      texto: s.ubicacion.isEmpty
                          ? 'Zona sin nombre'
                          : s.ubicacion,
                    ),
                    const SizedBox(height: 2),
                    _Dato(
                      icono: urgente
                          ? Icons.priority_high_rounded
                          : Icons.schedule_rounded,
                      texto: s.esMia
                          ? 'Asignada ${haceCuanto(s.fechaAsignacion ?? s.fechaCreacion, hoy).toLowerCase()}'
                          : 'Solicitada ${haceCuanto(s.fechaCreacion, hoy).toLowerCase()}',
                      color: urgente ? AppTheme.error : null,
                      negrita: urgente,
                    ),
                  ],
                ),
              ),
              if (recienAsignada) const _Etiqueta('NUEVA'),
            ],
          ),
          const SizedBox(height: 12),
          _ModalidadBadge(modalidad: s.modalidad),
          const SizedBox(height: 12),
          _ReglasSitio(reglas: s.reglasSitio),
          if (s.esMia) ...[
            const SizedBox(height: 12),
            _Direccion(direccion: s.direccion),
          ],
          if (s.estaDisponible) ...[
            const SizedBox(height: 16),
            _Acciones(
              solicitudId: s.id,
              accionEnCurso: accionEnCurso,
              bloqueada: bloqueada,
              onAceptar: onAceptar,
              onRechazar: onRechazar,
            ),
          ],
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({
    required this.icono,
    required this.texto,
    this.color,
    this.negrita = false,
  });

  final IconData icono;
  final String texto;
  final Color? color;
  final bool negrita;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textSecondary;
    return Row(
      children: [
        Icon(icono, size: 15, color: c),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: c,
              fontWeight: negrita ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModalidadBadge extends StatelessWidget {
  const _ModalidadBadge({required this.modalidad});

  final ModalidadServicio modalidad;

  @override
  Widget build(BuildContext context) {
    final (icono, texto, fondo) = switch (modalidad) {
      ModalidadServicio.cotizacionPrevia => (
        Icons.request_quote_outlined,
        'Requiere cotización antes de empezar',
        const Color(0xFFE0E7FF),
      ),
      ModalidadServicio.tarifaEstandar => (
        Icons.sell_outlined,
        'Tarifa estándar del tenant',
        const Color(0xFFDCFCE7),
      ),
      ModalidadServicio.desconocida => (
        Icons.help_outline,
        'Modalidad de cobro por confirmar',
        AppTheme.borderLight,
      ),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.dark, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 14, color: AppTheme.dark),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                texto,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.dark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reglas del sitio del cliente: el aliado las ve antes de aceptar (QS-06).
class _ReglasSitio extends StatelessWidget {
  const _ReglasSitio({required this.reglas});

  final List<ReglaSitio> reglas;

  @override
  Widget build(BuildContext context) {
    if (reglas.isEmpty) {
      return const _Dato(
        icono: Icons.check_circle_outline,
        texto: 'Sin reglas especiales en el sitio',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'REGLAS DEL SITIO',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
            color: AppTheme.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in reglas)
              Builder(
                builder: (_) {
                  final d = describirRegla(r);
                  return Container(
                    key: ValueKey('regla-${r.clave}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: d.advertencia
                          ? const Color(0xFFFEF3C7)
                          : AppTheme.background,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(
                        color: d.advertencia
                            ? const Color(0xFFB45309)
                            : AppTheme.borderLight,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(d.icono, size: 13, color: AppTheme.dark),
                        const SizedBox(width: 4),
                        Text(
                          d.texto,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _Direccion extends StatelessWidget {
  const _Direccion({required this.direccion});

  final String? direccion;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('direccion-solicitud'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.dark, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_rounded, color: AppTheme.dark),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DIRECCIÓN DEL SERVICIO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: Color(0xFF15803D),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  direccion ?? 'El cliente aún no registró la dirección.',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Acciones extends StatelessWidget {
  const _Acciones({
    required this.solicitudId,
    required this.accionEnCurso,
    required this.bloqueada,
    required this.onAceptar,
    required this.onRechazar,
  });

  final String solicitudId;
  final AccionSolicitud? accionEnCurso;
  final bool bloqueada;
  final VoidCallback? onAceptar;
  final VoidCallback? onRechazar;

  @override
  Widget build(BuildContext context) {
    final habilitada = !bloqueada && accionEnCurso == null;
    return Row(
      children: [
        Expanded(
          child: ManiButton(
            key: ValueKey('btn-rechazar-$solicitudId'),
            etiqueta: accionEnCurso == AccionSolicitud.rechazando
                ? 'Descartando…'
                : 'Rechazar',
            icono: Icons.close_rounded,
            variante: ManiButtonVariante.secundario,
            expandir: true,
            cargando: accionEnCurso == AccionSolicitud.rechazando,
            onPressed: habilitada ? onRechazar : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ManiButton(
            key: ValueKey('btn-aceptar-$solicitudId'),
            etiqueta: accionEnCurso == AccionSolicitud.aceptando
                ? 'Asegurando…'
                : 'Aceptar',
            icono: Icons.check_rounded,
            expandir: true,
            cargando: accionEnCurso == AccionSolicitud.aceptando,
            onPressed: habilitada ? onAceptar : null,
          ),
        ),
      ],
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.dark,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          color: AppTheme.primary,
        ),
      ),
    );
  }
}
