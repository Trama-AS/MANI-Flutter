import 'package:flutter/material.dart';
import 'package:mani/core/theme/app_theme.dart';

enum ManiButtonVariante { primario, peligro, secundario }

/// Botón neo-brutalista MANI. Al presionarlo "se hunde": la sombra dura
/// desaparece y el botón se desplaza a su posición, como un botón físico.
class ManiButton extends StatefulWidget {
  const ManiButton({
    super.key,
    required this.etiqueta,
    required this.onPressed,
    this.icono,
    this.variante = ManiButtonVariante.primario,
    this.cargando = false,
    this.expandir = false,
  });

  final String etiqueta;
  final VoidCallback? onPressed;
  final IconData? icono;
  final ManiButtonVariante variante;
  final bool cargando;
  final bool expandir;

  @override
  State<ManiButton> createState() => _ManiButtonState();
}

class _ManiButtonState extends State<ManiButton> {
  bool _presionado = false;

  bool get _habilitado => widget.onPressed != null && !widget.cargando;

  (Color fondo, Color texto) get _colores => switch (widget.variante) {
        ManiButtonVariante.primario => (AppTheme.primary, AppTheme.dark),
        ManiButtonVariante.peligro => (AppTheme.error, Colors.white),
        ManiButtonVariante.secundario => (AppTheme.surface, AppTheme.dark),
      };

  void _presionar(bool valor) {
    if (_habilitado && _presionado != valor) setState(() => _presionado = valor);
  }

  @override
  Widget build(BuildContext context) {
    final (fondo, texto) = _colores;
    final hundido = _presionado || !_habilitado;
    final estilo = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: texto,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        );

    final contenido = Row(
      mainAxisSize: widget.expandir ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.cargando)
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: texto),
          )
        else if (widget.icono != null)
          Icon(widget.icono, size: 18, color: texto),
        if (widget.cargando || widget.icono != null) const SizedBox(width: 8),
        Flexible(child: Text(widget.etiqueta, style: estilo, overflow: TextOverflow.ellipsis)),
      ],
    );

    return Semantics(
      button: true,
      enabled: _habilitado,
      label: widget.etiqueta,
      onTap: _habilitado ? widget.onPressed : null,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => _presionar(true),
        onTapUp: (_) => _presionar(false),
        onTapCancel: () => _presionar(false),
        onTap: _habilitado ? widget.onPressed : null,
        child: MouseRegion(
          cursor: _habilitado ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: _habilitado || widget.cargando ? 1 : 0.45,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              transform: Matrix4.translationValues(hundido ? 3 : 0, hundido ? 3 : 0, 0),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              decoration: BoxDecoration(
                color: fondo,
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                border: Border.all(color: AppTheme.dark, width: 2),
                boxShadow: [if (!hundido) AppTheme.hardShadowSm],
              ),
              child: contenido,
            ),
          ),
        ),
      ),
    );
  }
}
