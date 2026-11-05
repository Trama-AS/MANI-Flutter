import 'package:flutter/material.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_card.dart';

/// Ancho máximo del contenido de una página con sesión en escritorio.
const anchoMaximoPagina = 1400.0;

/// Página con sesión en el estilo de MANI: márgenes de escritorio, contenido
/// centrado hasta [anchoMaximoPagina] y scroll que construye todo (las
/// secciones existen aunque queden fuera de vista). Con [alRefrescar], se
/// recarga al deslizar hacia abajo.
class ManiPagina extends StatelessWidget {
  const ManiPagina({
    super.key,
    required this.children,
    this.alRefrescar,
    this.ancho = anchoMaximoPagina,
  });

  final List<Widget> children;
  final Future<void> Function()? alRefrescar;
  final double ancho;

  @override
  Widget build(BuildContext context) {
    final contenido = LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: c.maxWidth >= 600 ? 32 : 16,
          vertical: 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: ancho),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
    if (alRefrescar == null) return contenido;
    return RefreshIndicator(
      color: AppTheme.dark,
      backgroundColor: AppTheme.primary,
      onRefresh: alRefrescar!,
      child: contenido,
    );
  }
}

/// Encabezado de página: tarjeta con el ícono en caja amarilla, título y
/// descripción, y una acción opcional a la derecha (debajo en móvil). Es el
/// mismo de la pantalla del servicio.
class ManiEncabezadoPagina extends StatelessWidget {
  const ManiEncabezadoPagina({
    super.key,
    required this.icono,
    required this.titulo,
    this.descripcion,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String? descripcion;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final texto = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            border: Border.all(color: AppTheme.dark, width: 2),
            boxShadow: const [AppTheme.hardShadowSm],
          ),
          child: Icon(icono, color: AppTheme.dark, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.dark,
                ),
              ),
              if (descripcion != null) ...[
                const SizedBox(height: 4),
                Text(
                  descripcion!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return ManiCard(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, c) {
          if (accion == null) return texto;
          if (c.maxWidth < 600) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [texto, const SizedBox(height: 14), accion!],
            );
          }
          return Row(
            children: [
              Expanded(child: texto),
              const SizedBox(width: 16),
              accion!,
            ],
          );
        },
      ),
    );
  }
}

/// Título de sección: ícono en caja amarilla, texto en mayúsculas y subrayado
/// negro. Separa los bloques de una página (y las columnas del servicio).
class ManiTituloSeccion extends StatelessWidget {
  const ManiTituloSeccion({
    super.key,
    required this.icono,
    required this.titulo,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.dark, width: 2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.dark, width: 2),
            ),
            child: Icon(icono, color: AppTheme.dark, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              titulo.toUpperCase(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: AppTheme.dark,
              ),
            ),
          ),
          ?accion,
        ],
      ),
    );
  }
}

/// Reparte las tarjetas en columnas de igual ancho: tantas como quepan con
/// [anchoMinimo] cada una, hasta [maxColumnas]; una sola en móvil.
class ManiRejilla extends StatelessWidget {
  const ManiRejilla({
    super.key,
    required this.children,
    this.anchoMinimo = 320,
    this.maxColumnas = 3,
    this.espacio = 16,
  });

  final List<Widget> children;
  final double anchoMinimo;
  final int maxColumnas;
  final double espacio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final columnas = (c.maxWidth / anchoMinimo).floor().clamp(
          1,
          maxColumnas,
        );
        final ancho = (c.maxWidth - espacio * (columnas - 1)) / columnas;
        return Wrap(
          spacing: espacio,
          runSpacing: espacio,
          children: [
            for (final h in children) SizedBox(width: ancho, child: h),
          ],
        );
      },
    );
  }
}

/// Botón en píldora con borde negro: amarillo con sombra si es [principal],
/// blanco si no. Es el de las acciones de Mis solicitudes; el texto oscuro
/// sobre amarillo o blanco cumple el contraste AA.
class ManiBotonPildora extends StatelessWidget {
  const ManiBotonPildora({
    super.key,
    required this.etiqueta,
    required this.onPressed,
    this.icono,
    this.principal = false,
  });

  final String etiqueta;
  final VoidCallback? onPressed;
  final IconData? icono;
  final bool principal;

  @override
  Widget build(BuildContext context) {
    final estilo = TextButton.styleFrom(
      foregroundColor: AppTheme.dark,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: principal ? AppTheme.primary : AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.dark, width: 2),
        boxShadow: const [AppTheme.hardShadowSm],
      ),
      child: icono == null
          ? TextButton(
              onPressed: onPressed,
              style: estilo,
              child: Text(etiqueta),
            )
          : TextButton.icon(
              onPressed: onPressed,
              style: estilo,
              icon: Icon(icono, size: 18),
              label: Text(etiqueta),
            ),
    );
  }
}

/// Estado vacío o de error dentro de una página: tarjeta con ícono y texto,
/// y una acción opcional (p. ej. «Reintentar»).
class ManiAvisoTarjeta extends StatelessWidget {
  const ManiAvisoTarjeta({
    super.key,
    required this.icono,
    required this.texto,
    this.accion,
    this.esError = false,
  });

  final IconData icono;
  final String texto;
  final Widget? accion;
  final bool esError;

  @override
  Widget build(BuildContext context) {
    return ManiCard(
      color: esError ? const Color(0xFFFEE2E2) : AppTheme.surface,
      sombra: AppTheme.hardShadowSm,
      child: Row(
        children: [
          Icon(icono, color: esError ? const Color(0xFFB91C1C) : AppTheme.dark),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.dark,
              ),
            ),
          ),
          if (accion != null) ...[const SizedBox(width: 12), accion!],
        ],
      ),
    );
  }
}
