import 'package:flutter/material.dart';
import 'package:mani/core/theme/app_theme.dart';

/// Tarjeta neo-brutalista MANI: borde negro, esquinas redondeadas y sombra
/// dura. Si [seleccionada], resalta con fondo amarillo tenue y sombra mayor.
class ManiCard extends StatelessWidget {
  const ManiCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = AppTheme.surface,
    this.seleccionada = false,
    this.onTap,
    this.sombra = AppTheme.hardShadowMd,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final bool seleccionada;
  final VoidCallback? onTap;
  final BoxShadow? sombra;

  static const Color colorSeleccion = Color(0xFFFEF9C3);

  @override
  Widget build(BuildContext context) {
    final radio = BorderRadius.circular(AppTheme.radius2xl);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: seleccionada ? colorSeleccion : color,
        borderRadius: radio,
        border: Border.all(color: AppTheme.dark, width: 2),
        boxShadow: [
          if (sombra != null) seleccionada ? AppTheme.hardShadowLg : sombra!,
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radio,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
