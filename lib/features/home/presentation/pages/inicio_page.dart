import 'package:flutter/material.dart';
import 'package:mani/core/session/rol_usuario.dart';
import 'package:mani/core/shell/datos_sesion.dart';
import 'package:mani/core/shell/menu_por_rol.dart';
import 'package:mani/core/theme/app_theme.dart';
import 'package:mani/core/widgets/mani_card.dart';
import 'package:mani/features/home/data/resumen_inicio.dart';

/// Pantalla de inicio neo-brutalista por tipo de usuario (US-11.2.3 / SCRUM-1446).
///
/// Saluda con la sesión, muestra el resumen que cada rol necesita y repite
/// sus accesos como tarjetas centradas y estructuradas en escritorio.
class InicioPage extends StatefulWidget {
  const InicioPage({
    super.key,
    required this.rol,
    required this.fuenteSesion,
    required this.fuenteResumen,
    required this.onNavegar,
  });

  final RolUsuario rol;
  final FuenteDatosSesion fuenteSesion;
  final FuenteResumenInicio fuenteResumen;
  final ValueChanged<String> onNavegar;

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
    final accesos = entradasMenuPara(
      widget.rol,
    ).where((e) => e.ruta != '/inicio').toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            key: const Key('inicio-contenido'),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            children: [
              // ── Banner Hero Neo-Brutalista ──────────────────────────────
              ManiCard(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                        border: Border.all(color: AppTheme.dark, width: 2),
                        boxShadow: const [AppTheme.hardShadowSm],
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: AppTheme.dark,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FutureBuilder<DatosSesion>(
                            future: _sesion,
                            builder: (context, snap) => Text(
                              snap.hasData
                                  ? 'Hola, ${snap.data!.nombreUsuario}'
                                  : 'Hola',
                              key: const Key('inicio-saludo'),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.dark,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _subtitulo(widget.rol),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (widget.rol == RolUsuario.desconocido) ...[
                const SizedBox(height: 18),
                const Card(
                  key: Key('inicio-sin-rol'),
                  color: Color(0xFFFEF9C3),
                  child: ListTile(
                    leading: Icon(Icons.info_outline, color: AppTheme.dark),
                    title: Text(
                      'Tu cuenta no tiene un rol asignado',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      'Pide al administrador de tu empresa que revise tu cuenta.',
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              FutureBuilder<List<IndicadorResumen>>(
                future: _resumen,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator(color: AppTheme.dark),
                      ),
                    );
                  }
                  final indicadores = snap.data ?? const <IndicadorResumen>[];
                  if (indicadores.isEmpty) return const SizedBox.shrink();
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final i in indicadores)
                        _TarjetaIndicador(
                          indicador: i,
                          onTap: () => widget.onNavegar(i.ruta),
                        ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 28),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: AppTheme.dark, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Accesos Rápidos',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.dark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              for (final e in accesos) ...[
                ManiCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  sombra: AppTheme.hardShadowSm,
                  child: ListTile(
                    key: Key('inicio-acceso-${e.ruta}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(color: AppTheme.dark, width: 2),
                      ),
                      child: Icon(e.icono, color: AppTheme.dark, size: 20),
                    ),
                    title: Text(
                      e.etiqueta,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.dark,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(color: AppTheme.dark, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: AppTheme.dark,
                        size: 18,
                      ),
                    ),
                    onTap: () => widget.onNavegar(e.ruta),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
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

class _TarjetaIndicador extends StatelessWidget {
  const _TarjetaIndicador({required this.indicador, required this.onTap});

  final IndicadorResumen indicador;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: ManiCard(
        padding: EdgeInsets.zero,
        sombra: AppTheme.hardShadowSm,
        child: InkWell(
          key: Key('inicio-indicador-${indicador.etiqueta}'),
          borderRadius: BorderRadius.circular(AppTheme.radius2xl),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.dark, width: 1.5),
                  ),
                  child: Text(
                    indicador.valor ?? '—',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.dark,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  indicador.etiqueta,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.dark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
