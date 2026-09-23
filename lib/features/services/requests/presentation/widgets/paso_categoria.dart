import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_card.dart';

import '../bloc/crear_solicitud_cubit.dart';
import '../utils/estilo_solicitud.dart';
import 'encabezado_paso.dart';

/// Paso 1: ¿qué servicio necesitas? Un toque elige y avanza.
class PasoCategoria extends StatelessWidget {
  const PasoCategoria({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CrearSolicitudCubit>().state;
    final categorias = state.catalogo.categorias;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EncabezadoPaso(
          titulo: '¿Qué servicio necesitas?',
          subtitulo: 'Elige la categoría que mejor describe tu problema.',
        ),
        const SizedBox(height: 16),
        if (categorias.isEmpty)
          const _SinCategorias()
        else
          LayoutBuilder(
            builder: (context, c) {
              final columnas = c.maxWidth >= 560 ? 2 : 1;
              return GridView.count(
                crossAxisCount: columnas,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: columnas == 2 ? 2.6 : 4.2,
                children: [
                  for (final cat in categorias)
                    ManiCard(
                      key: ValueKey('categoria-${cat.id}'),
                      seleccionada: cat.id == state.categoriaId,
                      sombra: AppTheme.hardShadowSm,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      onTap: () => context
                          .read<CrearSolicitudCubit>()
                          .elegirCategoria(cat.id),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusXl,
                              ),
                              border: Border.all(
                                color: AppTheme.dark,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              iconoCategoria(cat.nombre),
                              color: AppTheme.dark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cat.nombre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  textoModalidad(cat.modalidad),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppTheme.textTertiary,
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _SinCategorias extends StatelessWidget {
  const _SinCategorias();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.dark, width: 2),
      ),
      child: const Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 36, color: AppTheme.dark),
          SizedBox(height: 10),
          Text(
            'Aún no hay servicios disponibles',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          SizedBox(height: 4),
          Text(
            'Tu empresa de servicios todavía no publicó categorías. '
            'Vuelve a intentarlo más tarde.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
