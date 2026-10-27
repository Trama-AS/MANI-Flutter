import 'package:flutter/material.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_button.dart';
import 'package:mani/core/widgets/mani_card.dart';

import '../../domain/entities/solicitud_publicada.dart';
import '../utils/estilo_solicitud.dart';

/// Confirmación: la solicitud quedó publicada y qué sigue.
class SolicitudPublicadaVista extends StatelessWidget {
  const SolicitudPublicadaVista({
    super.key,
    required this.solicitud,
    required this.onNueva,
    this.onReintentarAviso,
    this.avisando = false,
  });

  final SolicitudPublicada solicitud;
  final VoidCallback onNueva;

  /// Repite el aviso a los aliados si la publicación no lo logró (SCRUM-1402).
  final VoidCallback? onReintentarAviso;
  final bool avisando;

  @override
  Widget build(BuildContext context) {
    final s = solicitud;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.dark, width: 3),
                  boxShadow: const [AppTheme.hardShadowMd],
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  size: 40,
                  color: AppTheme.dark,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '¡Solicitud publicada!',
                key: ValueKey('titulo-publicada'),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                s.aliadosAvisados
                    ? 'Los aliados de ${s.categoria} en ${s.zona} ya pueden verla. '
                          'Te avisaremos cuando uno la tome.'
                    : 'Tu solicitud quedó guardada, pero todavía no pudimos '
                          'avisarle a los aliados.',
                key: const ValueKey('texto-publicada'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              if (!s.aliadosAvisados) ...[
                const SizedBox(height: 14),
                ManiButton(
                  key: const ValueKey('btn-reintentar-aviso'),
                  etiqueta: avisando ? 'Avisando…' : 'Avisar a los aliados',
                  icono: Icons.refresh_rounded,
                  expandir: true,
                  onPressed: avisando ? null : onReintentarAviso,
                ),
              ],
              const SizedBox(height: 20),
              ManiCard(
                sombra: AppTheme.hardShadowSm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(iconoCategoria(s.categoria), color: AppTheme.dark),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.categoria,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppTheme.dark,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            s.aliadosAvisados
                                ? 'BUSCANDO ALIADO'
                                : 'SIN AVISAR',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      s.descripcion,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    _Dato(icono: Icons.place_outlined, texto: s.direccion),
                    _Dato(icono: Icons.map_outlined, texto: s.ubicacion),
                    _Dato(
                      icono: Icons.photo_library_outlined,
                      texto: switch (s.cantidadFotos) {
                        0 => 'Sin fotos',
                        1 => '1 foto adjunta',
                        final n => '$n fotos adjuntas',
                      },
                    ),
                    _Dato(
                      icono: Icons.request_quote_outlined,
                      texto: textoModalidad(s.modalidad),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ManiButton(
                key: const ValueKey('btn-otra-solicitud'),
                etiqueta: 'Publicar otra solicitud',
                icono: Icons.add_rounded,
                expandir: true,
                onPressed: onNueva,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icono, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
