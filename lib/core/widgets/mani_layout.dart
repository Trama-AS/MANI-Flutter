import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mani/core/theme/app_theme.dart';

/// Ancho máximo del contenido en escritorio, el mismo de las pantallas de
/// registro: así todas las pantallas comparten columna y márgenes.
const anchoMaximoContenido = 1200.0;

/// Ancho a partir del cual las pantallas usan dos columnas, como el registro.
const anchoEscritorio = 850.0;

/// Centra el contenido con el ancho máximo y los márgenes del registro.
class ManiContenido extends StatelessWidget {
  const ManiContenido({super.key, required this.child, this.ancho});

  final Widget child;

  /// Ancho máximo propio, para formularios más angostos que la página.
  final double? ancho;

  static EdgeInsets margenes(double anchoPantalla) => anchoPantalla >= 600
      ? const EdgeInsets.symmetric(horizontal: 36, vertical: 24)
      : const EdgeInsets.all(16);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ancho ?? anchoMaximoContenido),
        child: child,
      ),
    );
  }
}

/// Banner de cabecera de una pantalla: ícono en caja amarilla, título y
/// descripción en tarjeta blanca con borde y sombra dura (registro).
class ManiEncabezado extends StatelessWidget {
  const ManiEncabezado({
    super.key,
    required this.icono,
    required this.titulo,
    this.descripcion,
    this.tituloKey,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String? descripcion;
  final Key? tituloKey;

  /// Botón opcional a la derecha (en móvil pasa debajo del texto).
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final texto = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          key: tituloKey,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppTheme.dark,
            letterSpacing: -0.4,
          ),
        ),
        if (descripcion != null) ...[
          const SizedBox(height: 4),
          Text(
            descripcion!,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: maniCaja(),
      child: LayoutBuilder(
        builder: (context, c) {
          final cabecera = Row(
            children: [
              ManiIconoCaja(icono: icono),
              const SizedBox(width: 16),
              Expanded(child: texto),
            ],
          );
          if (accion == null) return cabecera;
          if (c.maxWidth < 600) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [cabecera, const SizedBox(height: 16), accion!],
            );
          }
          return Row(
            children: [
              Expanded(child: cabecera),
              const SizedBox(width: 16),
              accion!,
            ],
          );
        },
      ),
    );
  }
}

/// Ícono sobre caja amarilla con borde, como en las tarjetas del registro.
class ManiIconoCaja extends StatelessWidget {
  const ManiIconoCaja({
    super.key,
    required this.icono,
    this.tamano = 26,
    this.color = AppTheme.primary,
  });

  final IconData icono;
  final double tamano;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(tamano >= 24 ? 12 : 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.dark, width: 2),
      ),
      child: Icon(icono, color: AppTheme.dark, size: tamano),
    );
  }
}

/// Título de una tarjeta de sección ("1. Datos del Cliente" en el registro).
class ManiTituloSeccion extends StatelessWidget {
  const ManiTituloSeccion({
    super.key,
    required this.icono,
    required this.texto,
  });

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, color: AppTheme.dark, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppTheme.dark,
            ),
          ),
        ),
      ],
    );
  }
}

/// Etiqueta en mayúsculas sobre cada campo ("CORREO ELECTRÓNICO").
class ManiEtiquetaCampo extends StatelessWidget {
  const ManiEtiquetaCampo(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        texto.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppTheme.dark,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Decoración de tarjeta del registro: blanco, borde de 2 px y sombra dura.
BoxDecoration maniCaja({
  Color color = AppTheme.surface,
  BoxShadow sombra = AppTheme.hardShadowMd,
}) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(AppTheme.radius2xl),
  border: Border.all(color: AppTheme.dark, width: 2),
  boxShadow: [sombra],
);
