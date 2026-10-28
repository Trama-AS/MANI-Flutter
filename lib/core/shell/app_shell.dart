import 'package:flutter/material.dart';
import 'package:mani/core/session/rol_usuario.dart';
import 'package:mani/core/shell/datos_sesion.dart';
import 'package:mani/core/shell/menu_por_rol.dart';

/// Ancho a partir del cual las entradas se muestran como barra; por debajo
/// se agrupan en un menú desplegable para que quepan en móvil (RNF-08).
const anchoMenuExpandido = 600.0;

/// Armazón de las pantallas con sesión (US-11.2.1 / SCRUM-1444).
///
/// Pinta el menú superior con las entradas del [rol], el usuario y el tenant
/// de la sesión, y la acción de cerrar sesión en todas las pantallas. La
/// pantalla de cada ruta llega como [child] y conserva su propio título.
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

  bool _esActiva(EntradaMenu e) =>
      widget.ubicacion == e.ruta || widget.ubicacion.startsWith('${e.ruta}/');

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
          appBar: AppBar(
            key: const Key('menu-superior'),
            automaticallyImplyLeading: false,
            leading: expandido ? null : _menuCompacto(entradas),
            titleSpacing: expandido ? null : 0,
            title: _CabeceraSesion(datos: _datos, rol: widget.rol),
            actions: [
              IconButton(
                key: const Key('menu-cerrar-sesion'),
                tooltip: 'Cerrar sesión',
                icon: const Icon(Icons.logout),
                onPressed: _cerrarSesion,
              ),
            ],
            bottom: expandido ? _barraEntradas(context, entradas) : null,
          ),
          body: widget.child,
        );
      },
    );
  }

  Widget _menuCompacto(List<EntradaMenu> entradas) {
    return PopupMenuButton<String>(
      key: const Key('menu-compacto'),
      tooltip: 'Menú',
      icon: const Icon(Icons.menu),
      onSelected: widget.onNavegar,
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
      ],
    );
  }

  PreferredSizeWidget _barraEntradas(
    BuildContext context,
    List<EntradaMenu> entradas,
  ) {
    final esquema = Theme.of(context).colorScheme;
    return PreferredSize(
      preferredSize: const Size.fromHeight(48),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (final e in entradas)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextButton.icon(
                    key: Key('menu-entrada-${e.ruta}'),
                    onPressed: () => widget.onNavegar(e.ruta),
                    icon: Icon(e.icono, size: 20),
                    label: Text(e.etiqueta),
                    style: TextButton.styleFrom(
                      foregroundColor: _esActiva(e)
                          ? esquema.primary
                          : esquema.onSurfaceVariant,
                      backgroundColor: _esActiva(e)
                          ? esquema.primaryContainer.withValues(alpha: 0.5)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Usuario, rol y tenant de la sesión. Mientras carga muestra solo el rol, y
/// si Core no responde muestra el rol sin nombre: el menú sigue usable.
class _CabeceraSesion extends StatelessWidget {
  const _CabeceraSesion({required this.datos, required this.rol});

  final Future<DatosSesion> datos;
  final RolUsuario rol;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return FutureBuilder<DatosSesion>(
      future: datos,
      builder: (context, snap) {
        final d = snap.data;
        final usuario = d?.nombreUsuario;
        final linea2 = [
          etiquetaRol(rol),
          if (d?.nombreTenant != null) d!.nombreTenant!,
        ].join(' · ');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              usuario ?? 'MANI',
              key: const Key('menu-usuario'),
              style: tema.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              linea2,
              key: const Key('menu-tenant'),
              style: tema.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }
}
