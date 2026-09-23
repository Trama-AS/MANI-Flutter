import 'package:flutter/material.dart';
import 'package:mani/core/theme/app_theme.dart';

import '../../domain/entities/documento_kyc.dart';
import '../utils/formato_fecha.dart';

/// Fila de un documento KYC con acción para abrirlo en un visor.
class DocumentoKycTile extends StatelessWidget {
  const DocumentoKycTile({
    super.key,
    required this.documento,
    required this.onVer,
  });

  final DocumentoKyc documento;
  final VoidCallback onVer;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final (colorEstado, textoEstado) = switch (documento.estado) {
      EstadoDocumentoKyc.pendiente => (const Color(0xFFB45309), 'Por revisar'),
      EstadoDocumentoKyc.verificado => (const Color(0xFF15803D), 'Verificado'),
      EstadoDocumentoKyc.rechazado => (const Color(0xFFB91C1C), 'Rechazado'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.dark, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: documento.esImagen
                  ? const Color(0xFFE0E7FF)
                  : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.dark, width: 1.5),
            ),
            child: Icon(
              documento.esImagen
                  ? Icons.image_outlined
                  : Icons.picture_as_pdf_outlined,
              color: AppTheme.dark,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  documento.tipo.etiqueta,
                  style: tema.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    documento.nombreArchivo,
                    if (documento.fechaCarga != null)
                      fechaCorta(documento.fechaCarga!),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tema.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  textoEstado,
                  style: tema.labelSmall?.copyWith(
                    color: colorEstado,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: ValueKey('ver-doc-${documento.id}'),
            onPressed: onVer,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Ver'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.dark,
              side: const BorderSide(color: AppTheme.dark, width: 1.5),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
