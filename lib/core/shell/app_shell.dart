import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mani/core/session/rol_usuario.dart';
import 'package:mani/core/shell/datos_sesion.dart';
import 'package:mani/core/shell/menu_por_rol.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_layout.dart';

/// Ancho a partir del cual las entradas se muestran como barra; por debajo
/// se agrupan en un menú desplegable para que quepan en móvil (RNF-08).
const anchoMenuExpandido = 600.0;

/// Armazón de las pantallas con sesión (US-11.2.1 / SCRUM-1444).
///
/// Pinta el menú superior con las entradas del [rol], el usuario y el tenant
/// de la sesión, y la acción de cerrar sesión en todas las pantallas. Usa la
/// barra superior de las pantallas de registro (logo, borde negro) y centra el
/// contenido con el mismo ancho máximo. La pantalla de cada ruta llega como
/// [child] y conserva su propio título.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.child,
    required this.rol,
    required this.ubicacion,
    required this.fuenteDatos,
    required this.onNavegar,
    required this.onCerrarSesion,
  });

  final Widget child;
  final RolUsuario rol;

  /// Ruta actual (`state.matchedLocation`), para resaltar la entrada activa.
  final String ubicacion;
  final FuenteDatosSesion fuenteDatos;
  final ValueChanged<String> onNavegar;
  final Future<void> Function() onCerrarSesion;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late Future<DatosSesion> _datos;

  @override
  void initState() {
    super.initState();
    _datos = widget.fuenteDatos.cargar();
  }

  bool _coincide(EntradaMenu e) =>
      widget.ubicacion == e.ruta || widget.ubicacion.startsWith('${e.ruta}/');

  /// Solo la entrada más específica queda activa: en
  /// `/cliente/solicitudes/nueva` se resalta "Nueva solicitud" y no también
  /// "Mis solicitudes".
  bool _esActiva(EntradaMenu e) {
    if (!_coincide(e)) return false;
    return !entradasMenuPara(
      widget.rol,
    ).any((o) => o.ruta.length > e.ruta.length && _coincide(o));
  }

  Future<void> _cerrarSesion() async {
    await widget.onCerrarSesion();
  }

  @override
  Widget build(BuildContext context) {
    final entradas = entradasMenuPara(widget.rol);
    return LayoutBuilder(
      builder: (context, constraints) {
        final expandido = constraints.maxWidth >= anchoMenuExpandido;
        return Scaffold(
          key: const Key('app-shell'),
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            key: const Key('menu-superior'),
            automaticallyImplyLeading: false,
            backgroundColor: AppTheme.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            toolbarHeight: 68,
            shape: const Border(
              bottom: BorderSide(color: AppTheme.dark, width: 2),
            ),
            leading: expandido ? null : _menuCompacto(entradas),
            titleSpacing: expandido ? 32 : 0,
            title: _CabeceraSesion(
              datos: _datos,
              rol: widget.rol,
              conLogo: expandido,
            ),
            actions: [
              Padding(
                padding: EdgeInsets.only(right: expandido ? 32 : 8),
                child: expandido
                    ? OutlinedButton.icon(
                        key: const Key('menu-cerrar-sesion'),
                        onPressed: _cerrarSesion,
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Cerrar sesión'),
                      )
                    : IconButton(
                        key: const Key('menu-cerrar-sesion'),
                        tooltip: 'Cerrar sesión',
                        icon: const Icon(Icons.logout),
                        onPressed: _cerrarSesion,
                      ),
              ),
            ],
            bottom: expandido ? _barraEntradas(entradas) : null,
          ),
          body: ManiContenido(child: widget.child),
        );
      },
    );
  }

  Widget _menuCompacto(List<EntradaMenu> entradas) {
    return PopupMenuButton<String>(
      key: const Key('menu-compacto'),
      tooltip: 'Menú',
      icon: const Icon(Icons.menu),
      onSelected: (val) {
        if (val == '__logout__') {
          _cerrarSesion();
        } else {
          widget.onNavegar(val);
        }
      },
      itemBuilder: (context) => [
        for (final e in entradas)
          PopupMenuItem<String>(
            key: Key('menu-entrada-${e.ruta}'),
            value: e.ruta,
            child: ListTile(
              leading: Icon(e.icono),
              title: Text(e.etiqueta),
              selected: _esActiva(e),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          key: Key('menu-compacto-cerrar-sesion'),
          value: '__logout__',
          child: ListTile(
            leading: Icon(Icons.logout, color: AppTheme.error),
            title: Text(
              'Cerrar sesión',
              style: TextStyle(
                color: AppTheme.error,
                fontWeight: FontWeight.w800,
              ),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  PreferredSizeWidget _barraEntradas(List<EntradaMenu> entradas) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(62),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.borderLight)),
        ),
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(28, 10, 28, 12),
          child: Row(
            children: [
              for (final e in entradas)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _EntradaBarra(
                    entrada: e,
                    activa: _esActiva(e),
                    onTap: () => widget.onNavegar(e.ruta),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entrada del menú: pastilla amarilla con borde y sombra dura si está
/// activa, texto plano si no; mismo lenguaje que los botones del registro.
class _EntradaBarra extends StatelessWidget {
  const _EntradaBarra({
    required this.entrada,
    required this.activa,
    required this.onTap,
  });

  final EntradaMenu entrada;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        boxShadow: [if (activa) AppTheme.hardShadowSm],
      ),
      child: TextButton.icon(
        key: Key('menu-entrada-${entrada.ruta}'),
        onPressed: onTap,
        icon: Icon(entrada.icono, size: 18),
        label: Text(entrada.etiqueta),
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.dark,
          backgroundColor: activa ? AppTheme.primary : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            side: BorderSide(
              color: activa ? AppTheme.dark : Colors.transparent,
              width: 2,
            ),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: activa ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Logo, usuario, rol y tenant de la sesión. Mientras carga muestra solo el
/// rol, y si Core no responde muestra el rol sin nombre: el menú sigue usable.
class _CabeceraSesion extends StatelessWidget {
  const _CabeceraSesion({
    required this.datos,
    required this.rol,
    this.conLogo = true,
  });

  final Future<DatosSesion> datos;
  final RolUsuario rol;
  final bool conLogo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DatosSesion>(
      future: datos,
      builder: (context, snap) {
        final d = snap.data;
        final usuario = d?.nombreUsuario;
        final linea2 = [
          etiquetaRol(rol),
          if (d?.nombreTenant != null) d!.nombreTenant!,
        ].join(' · ');
        return Row(
          children: [
            if (conLogo) ...[
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(color: AppTheme.dark, width: 2),
                  boxShadow: const [AppTheme.hardShadowSm],
                ),
                child: Text(
                  'M',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.dark,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    usuario ?? 'MANI',
                    key: const Key('menu-usuario'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.dark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    linea2,
                    key: const Key('menu-tenant'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
