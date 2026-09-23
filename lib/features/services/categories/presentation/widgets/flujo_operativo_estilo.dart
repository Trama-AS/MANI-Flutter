import 'package:flutter/material.dart';
import 'package:mani/core/theme/app_theme.dart';

import '../../domain/entities/flujo_operativo.dart';

/// Ícono y colores de cada flujo, compartidos por tarjetas, selector y badge.
extension EstiloFlujoOperativo on FlujoOperativo {
  IconData get icono => switch (this) {
    FlujoOperativo.cotizacionPrevia => Icons.request_quote_outlined,
    FlujoOperativo.tarifaEstandar => Icons.sell_outlined,
  };

  Color get fondo => switch (this) {
    FlujoOperativo.cotizacionPrevia => const Color(0xFFE0E7FF),
    FlujoOperativo.tarifaEstandar => const Color(0xFFDCFCE7),
  };

  Color get acento => switch (this) {
    FlujoOperativo.cotizacionPrevia => const Color(0xFF3730A3),
    FlujoOperativo.tarifaEstandar => const Color(0xFF15803D),
  };

  /// Cómo lo lee el cliente en el catálogo.
  String get textoCliente => switch (this) {
    FlujoOperativo.cotizacionPrevia =>
      'Recibirás una cotización antes de empezar',
    FlujoOperativo.tarifaEstandar => 'Precio fijo de referencia',
  };
}

class FlujoOperativoBadge extends StatelessWidget {
  const FlujoOperativoBadge({super.key, required this.flujo});

  /// `null` = flujo desconocido en BD.
  final FlujoOperativo? flujo;

  @override
  Widget build(BuildContext context) {
    final f = flujo;
    final fondo = f?.fondo ?? AppTheme.borderLight;
    final acento = f?.acento ?? AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.dark, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(f?.icono ?? Icons.help_outline, size: 13, color: acento),
          const SizedBox(width: 4),
          Text(
            f?.etiqueta ?? 'Flujo sin definir',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: acento,
            ),
          ),
        ],
      ),
    );
  }
}
