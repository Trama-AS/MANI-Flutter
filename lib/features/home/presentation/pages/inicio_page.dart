import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mani/core/session/rol_usuario.dart';
import 'package:mani/core/shell/datos_sesion.dart';
import 'package:mani/core/shell/menu_por_rol.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_card.dart';
import 'package:mani/core/widgets/mani_layout.dart';
import 'package:mani/features/home/data/resumen_inicio.dart';

/// Pantalla de inicio por tipo de usuario (US-11.2.3 / SCRUM-1446).
///
/// Saluda con la sesión, muestra el resumen que cada rol necesita y repite
/// sus accesos como tarjetas. Vive dentro del menú superior (SCRUM-1444).
class InicioPage extends StatefulWidget {
  const InicioPage({
    super.key,
    required this.rol,
    required this.fuenteSesion,
    required this.fuenteResumen,
    required this.onNavegar,
    this.onCerrarSesion,
  });

  final RolUsuario rol;
  final FuenteDatosSesion fuenteSesion;
  final FuenteResumenInicio fuenteResumen;
  final ValueChanged<String> onNavegar;
  final Future<void> Function()? onCerrarSesion;

  @override
  State<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends State<InicioPage> {
  late Future<DatosSesion> _sesion;
  late Future<List<IndicadorResumen>> _resumen;

  @override
  void initState() {
    super.initState();
    _sesion = widget.fuenteSesion.cargar();
    _resumen = widget.fuenteResumen.cargar(widget.rol);
  }

  @override
  Widget build(BuildContext context) {
    final accesos = entradasMenuPara(widget.rol)
        .where((e) => e.ruta != '/inicio')
        .toList();
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) => ListView(
          key: const Key('inicio-contenido'),
          padding: ManiContenido.margenes(c.maxWidth),
          children: [
            FutureBuilder<DatosSesion>(
              future: _sesion,
              builder: (context, snap) => ManiEncabezado(
                icono: Icons.waving_hand_outlined,
                titulo: snap.hasData
                    ? 'Hola, ${snap.data!.nombreUsuario}'
                    : 'Hola',
                tituloKey: const Key('inicio-saludo'),
                descripcion: _subtitulo(widget.rol),
              ),
            ),
            if (widget.rol == RolUsuario.desconocido) ...[
              const SizedBox(height: 24),
              const ManiCard(
                key: Key('inicio-sin-rol'),
                color: ManiCard.colorSeleccion,
                child: Row(
                  children: [
                    ManiIconoCaja(icono: Icons.info_outline, tamano: 18),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tu cuenta no tiene un rol asignado',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Pide al administrador de tu empresa que revise tu cuenta.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            FutureBuilder<List<IndicadorResumen>>(
              future: _resumen,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final indicadores = snap.data ?? const <IndicadorResumen>[];
                if (indicadores.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ManiTituloSeccion(
                        icono: Icons.insights_outlined,
                        texto: 'Resumen',
                      ),
                      const SizedBox(height: 14),
                      _Rejilla(
                        anchoMinimo: 220,
                        children: [
                          for (final i in indicadores)
                            _TarjetaIndicador(
                              indicador: i,
                              onTap: () => widget.onNavegar(i.ruta),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 28),
            const ManiTituloSeccion(
              icono: Icons.apps_rounded,
              texto: 'Accesos',
            ),
            const SizedBox(height: 14),
            _Rejilla(
              anchoMinimo: 300,
              children: [
                for (final e in accesos)
                  ManiCard(
                    onTap: () => widget.onNavegar(e.ruta),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: Row(
                      key: Key('inicio-acceso-${e.ruta}'),
                      children: [
                        ManiIconoCaja(icono: e.icono, tamano: 18),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            e.etiqueta,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.dark,
                            ),
                          ),
                        ),
                        const Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
                  ),
              ],
            ),
            if (widget.onCerrarSesion != null) ...[
              const SizedBox(height: 28),
              ManiCard(
                key: const Key('inicio-card-sesion'),
                onTap: () async {
                  await widget.onCerrarSesion!();
                },
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Row(
                  key: const Key('inicio-cerrar-sesion'),
                  children: [
                    const ManiIconoCaja(
                      icono: Icons.logout,
                      tamano: 18,
                      color: Color(0xFFFEE2E2),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cerrar sesión',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.error,
                            ),
                          ),
                          Text(
                            'Finaliza la sesión actual en este dispositivo',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward, color: AppTheme.error),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static String _subtitulo(RolUsuario rol) {
    switch (rol) {
      case RolUsuario.cliente:
        return 'Publica solicitudes y administra tus sedes.';
      case RolUsuario.aliado:
        return 'Revisa las solicitudes y mantén al día tu cobertura.';
      case RolUsuario.adminTenant:
        return 'Verifica aliados y administra el catálogo de tu empresa.';
      case RolUsuario.desconocido:
        return 'Solo puedes consultar tu perfil por ahora.';
    }
  }
}

/// Reparte las tarjetas en columnas iguales según el ancho disponible: tres en
/// escritorio, dos en tableta y una en móvil.
class _Rejilla extends StatelessWidget {
  const _Rejilla({required this.anchoMinimo, required this.children});

  final double anchoMinimo;
  final List<Widget> children;

  static const _espacio = 20.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final columnas = (c.maxWidth / anchoMinimo).floor().clamp(1, 4);
        final ancho = (c.maxWidth - _espacio * (columnas - 1)) / columnas;
        return Wrap(
          spacing: _espacio,
          runSpacing: _espacio,
          children: [
            for (final h in children) SizedBox(width: ancho, child: h),
          ],
        );
      },
    );
  }
}

class _TarjetaIndicador extends StatelessWidget {
  const _TarjetaIndicador({required this.indicador, required this.onTap});

  final IndicadorResumen indicador;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ManiCard(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      child: Column(
        key: Key('inicio-indicador-${indicador.etiqueta}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            indicador.valor ?? '—',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: AppTheme.dark,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            indicador.etiqueta,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
