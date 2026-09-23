import 'package:flutter/material.dart';
import 'package:mani/core/theme/app_theme.dart';

import '../../domain/entities/solicitud_aliado.dart';

/// Colores e ícono de cada estado, compartidos por badges, pestañas y panel.
extension EstiloEstadoVerificacion on EstadoVerificacion {
  Color get fondo => switch (this) {
    EstadoVerificacion.pendiente => const Color(0xFFFEF3C7),
    EstadoVerificacion.aprobado => const Color(0xFFDCFCE7),
    EstadoVerificacion.rechazado => const Color(0xFFFEE2E2),
  };

  Color get acento => switch (this) {
    EstadoVerificacion.pendiente => const Color(0xFFB45309),
    EstadoVerificacion.aprobado => const Color(0xFF15803D),
    EstadoVerificacion.rechazado => const Color(0xFFB91C1C),
  };

  IconData get icono => switch (this) {
    EstadoVerificacion.pendiente => Icons.hourglass_top_rounded,
    EstadoVerificacion.aprobado => Icons.verified_rounded,
    EstadoVerificacion.rechazado => Icons.block_rounded,
  };
}

class EstadoVerificacionBadge extends StatelessWidget {
  const EstadoVerificacionBadge({
    super.key,
    required this.estado,
    this.compacto = false,
  });

  final EstadoVerificacion estado;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 8 : 10,
        vertical: compacto ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: estado.fondo,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.dark, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(estado.icono, size: compacto ? 12 : 14, color: estado.acento),
          const SizedBox(width: 4),
          Text(
            estado.etiqueta.toUpperCase(),
            style: TextStyle(
              fontSize: compacto ? 10 : 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: estado.acento,
            ),
          ),
        ],
      ),
    );
  }
}
