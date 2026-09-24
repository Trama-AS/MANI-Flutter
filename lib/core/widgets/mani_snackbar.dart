import 'package:flutter/material.dart';
import 'package:mani/core/theme/app_theme.dart';

/// SnackBar flotante con el estilo MANI (rojo para errores, amarillo para éxito).
/// [margin] permite elevarla sobre barras de acción fijas para no taparlas.
void showManiSnackBar(
  BuildContext context,
  String mensaje, {
  bool esError = false,
  EdgeInsetsGeometry margin = const EdgeInsets.all(16),
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          mensaje,
          style: TextStyle(
            color: esError ? Colors.white : AppTheme.dark,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: esError ? AppTheme.error : AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          side: const BorderSide(color: AppTheme.dark, width: 2),
        ),
        margin: margin,
      ),
    );
}
