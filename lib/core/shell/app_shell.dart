import 'package:flutter/material.dart';
import 'package:mani/core/session/rol_usuario.dart';
import 'package:mani/core/shell/datos_sesion.dart';
import 'package:mani/core/shell/menu_por_rol.dart';
import 'package:mani/core/theme/app_theme.dart';

/// Ancho a partir del cual las entradas se muestran como barra; por debajo
/// se agrupan en un menú desplegable para que quepan en móvil (RNF-08).
const anchoMenuExpandido = 600.0;

/// Armazón neo-brutalista de las pantallas con sesión (US-11.2.1 / SCRUM-1444).
///
/// Pinta el menú superior centrado en escritorio con las entradas del [rol],
/// el usuario y el tenant de la sesión, y la acción de cerrar sesión.
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
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            key: const Key('menu-superior'),
            automaticallyImplyLeading: false,
            backgroundColor: AppTheme.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 68,
            shape: const Border(
              bottom: BorderSide(color: AppTheme.dark, width: 2),
            ),
            leading: expandido ? null : _menuCompacto(entradas),
            titleSpacing: expandido ? 32 : 0,
            title: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
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
                    child: const Text(
                      'M',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.dark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CabeceraSesion(datos: _datos, rol: widget.rol),
                  ),
                ],
              ),
            ),
            actions: [
              Padding(
                padding: EdgeInsets.only(right: expandido ? 32 : 16),
                child: Center(
                  child: expandido
                      ? OutlinedButton.icon(
                          key: const Key('menu-cerrar-sesion'),
                          onPressed: _cerrarSesion,
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: const Text('Cerrar sesión'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.dark,
                            backgroundColor: AppTheme.surface,
                            side: const BorderSide(
                              color: AppTheme.dark,
                              width: 2,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusXl,
                              ),
                            ),
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMd,
                            ),
                            border: Border.all(color: AppTheme.dark, width: 2),
                            boxShadow: const [AppTheme.hardShadowSm],
                          ),
                          child: IconButton(
                            key: const Key('menu-cerrar-sesion'),
                            tooltip: 'Cerrar sesión',
                            icon: const Icon(
                              Icons.logout_rounded,
                              color: AppTheme.dark,
                              size: 20,
                            ),
                            onPressed: _cerrarSesion,
                          ),
                        ),
                ),
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
      icon: const Icon(Icons.menu_rounded, color: AppTheme.dark),
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
              leading: Icon(e.icono, color: AppTheme.dark),
              title: Text(
                e.etiqueta,
                style: TextStyle(
                  fontWeight: _esActiva(e) ? FontWeight.w900 : FontWeight.w600,
                  color: AppTheme.dark,
                ),
              ),
              selected: _esActiva(e),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          key: Key('menu-compacto-cerrar-sesion'),
          value: '__logout__',
          child: ListTile(
            leading: Icon(Icons.logout, color: Colors.redAccent),
            title: Text(
              'Cerrar sesión',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
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
    return PreferredSize(
      preferredSize: const Size.fromHeight(58),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppTheme.background,
          border: Border(top: BorderSide(color: AppTheme.dark, width: 1.5)),
        ),
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 27, vertical: 8),
          child: Row(
            children: [
              for (final e in entradas)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _esActiva(e) ? AppTheme.primary : AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                      border: Border.all(color: AppTheme.dark, width: 2),
                      boxShadow: _esActiva(e)
                          ? const [AppTheme.hardShadowSm]
                          : const [],
                    ),
                    child: TextButton.icon(
                      key: Key('menu-entrada-${e.ruta}'),
                      onPressed: () => widget.onNavegar(e.ruta),
                      icon: Icon(e.icono, size: 18, color: AppTheme.dark),
                      label: Text(
                        e.etiqueta,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _esActiva(e)
                              ? FontWeight.w900
                              : FontWeight.w700,
                          color: AppTheme.dark,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.dark,
                        backgroundColor: _esActiva(e) ? AppTheme.primary : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusXl,
                          ),
                        ),
                      ),
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
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppTheme.dark,
                letterSpacing: -0.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              linea2,
              key: const Key('menu-tenant'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }
}
