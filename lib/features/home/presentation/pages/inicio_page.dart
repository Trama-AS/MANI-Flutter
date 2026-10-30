import 'package:flutter/material.dart';
import 'package:mani/core/session/rol_usuario.dart';
import 'package:mani/core/shell/datos_sesion.dart';
import 'package:mani/core/shell/menu_por_rol.dart';
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
    final tema = Theme.of(context).textTheme;
    final accesos = entradasMenuPara(
      widget.rol,
    ).where((e) => e.ruta != '/inicio').toList();
    return Scaffold(
      body: ListView(
        key: const Key('inicio-contenido'),
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<DatosSesion>(
            future: _sesion,
            builder: (context, snap) => Text(
              snap.hasData ? 'Hola, ${snap.data!.nombreUsuario}' : 'Hola',
              key: const Key('inicio-saludo'),
              style: tema.headlineSmall,
            ),
          ),
          const SizedBox(height: 4),
          Text(_subtitulo(widget.rol), style: tema.bodyMedium),
          if (widget.rol == RolUsuario.desconocido) ...[
            const SizedBox(height: 16),
            const Card(
              key: Key('inicio-sin-rol'),
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Tu cuenta no tiene un rol asignado'),
                subtitle: Text(
                  'Pide al administrador de tu empresa que revise tu cuenta.',
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FutureBuilder<List<IndicadorResumen>>(
            future: _resumen,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final indicadores = snap.data ?? const <IndicadorResumen>[];
              if (indicadores.isEmpty) return const SizedBox.shrink();
              return Wrap(
                spacing: 12,
                runSpacing: 12,
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
          const SizedBox(height: 24),
          Text('Accesos', style: tema.titleMedium),
          const SizedBox(height: 8),
          for (final e in accesos)
            Card(
              child: ListTile(
                key: Key('inicio-acceso-${e.ruta}'),
                leading: Icon(e.icono),
                title: Text(e.etiqueta),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.onNavegar(e.ruta),
              ),
            ),
        ],
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
      case RolUsuario.adminPlataforma:
        return 'Habilita o suspende los tenants de la plataforma.';
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
    final tema = Theme.of(context).textTheme;
    return SizedBox(
      width: 200,
      child: Card(
        child: InkWell(
          key: Key('inicio-indicador-${indicador.etiqueta}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(indicador.valor ?? '—', style: tema.headlineMedium),
                const SizedBox(height: 4),
                Text(indicador.etiqueta, style: tema.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
