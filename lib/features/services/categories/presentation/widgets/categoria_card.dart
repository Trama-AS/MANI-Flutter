import 'package:flutter/material.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_card.dart';

import '../../domain/entities/categoria_servicio.dart';
import 'flujo_operativo_estilo.dart';

/// Tarjeta de una categoría en el catálogo del administrador.
class CategoriaCard extends StatelessWidget {
  const CategoriaCard({
    super.key,
    required this.categoria,
    this.recienCreada = false,
    this.cambiandoEstado = false,
    this.onCambiarEstado,
  });

  final CategoriaServicio categoria;

  /// Resalta la tarjeta justo después de crearla.
  final bool recienCreada;

  /// Indica que se está enviando el cambio de estado (`ACTIVO` / `INACTIVO`).
  final bool cambiandoEstado;

  /// Callback para ocultar o activar la categoría sin cancelar servicios en curso.
  final ValueChanged<bool>? onCambiarEstado;

  @override
  Widget build(BuildContext context) {
    final c = categoria;
    return ManiCard(
      key: ValueKey('card-categoria-${c.id}'),
      seleccionada: recienCreada,
      sombra: AppTheme.hardShadowSm,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.flujo?.fondo ?? AppTheme.background,
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                  border: Border.all(color: AppTheme.dark, width: 2),
                ),
                child: Icon(
                  Icons.home_repair_service_rounded,
                  color: AppTheme.dark,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.dark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _EstadoVisibilidad(activa: c.activa),
                  ],
                ),
              ),
              if (recienCreada) const _EtiquetaNueva(),
            ],
          ),
          const SizedBox(height: 10),
          FlujoOperativoBadge(flujo: c.flujo),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.engineering_outlined,
                size: 14,
                color: AppTheme.textTertiary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  switch (c.aliadosAsociados) {
                    0 => 'Aún sin aliados',
                    1 => '1 aliado',
                    final n => '$n aliados',
                  },
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              if (onCambiarEstado != null) ...[
                const SizedBox(width: 8),
                _BotonVisibilidad(
                  categoriaId: c.id,
                  activa: c.activa,
                  cargando: cambiandoEstado,
                  onTap: () => onCambiarEstado!(!c.activa),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _BotonVisibilidad extends StatelessWidget {
  const _BotonVisibilidad({
    required this.categoriaId,
    required this.activa,
    required this.cargando,
    required this.onTap,
  });

  final String categoriaId;
  final bool activa;
  final bool cargando;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: activa
          ? 'Ocultar del catálogo público sin afectar servicios en curso'
          : 'Volver a mostrar en el catálogo público',
      child: Material(
        color: activa ? AppTheme.background : AppTheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: InkWell(
          key: ValueKey('toggle-estado-categoria-$categoriaId'),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          onTap: cargando ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: AppTheme.dark, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cargando)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.dark,
                    ),
                  )
                else
                  Icon(
                    activa
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 13,
                    color: AppTheme.dark,
                  ),
                const SizedBox(width: 4),
                Text(
                  cargando ? 'Guardando...' : (activa ? 'Ocultar' : 'Activar'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.dark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EstadoVisibilidad extends StatelessWidget {
  const _EstadoVisibilidad({required this.activa});

  final bool activa;

  @override
  Widget build(BuildContext context) {
    final color = activa ? AppTheme.success : AppTheme.textTertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          activa ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            activa ? 'Visible para clientes' : 'Oculta',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: activa ? const Color(0xFF15803D) : AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _EtiquetaNueva extends StatelessWidget {
  const _EtiquetaNueva();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.dark,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: const Text(
        'NUEVA',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          color: AppTheme.primary,
        ),
      ),
    );
  }
}
