import 'package:flutter/material.dart';
import 'package:mani/core/theme/app_theme.dart';

import '../../domain/entities/solicitud_aliado.dart';

/// Avatar cuadrado con las iniciales del aliado; ícono de edificio si es empresa.
class AliadoAvatar extends StatelessWidget {
  const AliadoAvatar({super.key, required this.aliado, this.tamano = 48});

  final SolicitudAliado aliado;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final esEmpresa = aliado.tipo == TipoAliado.empresa;
    return Container(
      width: tamano,
      height: tamano,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: esEmpresa ? const Color(0xFFDBEAFE) : AppTheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.dark, width: 2),
      ),
      child: esEmpresa
          ? Icon(
              Icons.apartment_rounded,
              color: AppTheme.dark,
              size: tamano * 0.5,
            )
          : Text(
              aliado.iniciales,
              style: TextStyle(
                fontSize: tamano * 0.36,
                fontWeight: FontWeight.w900,
                color: AppTheme.dark,
              ),
            ),
    );
  }
}
