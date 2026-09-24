import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/theme/app_theme.dart';

import '../../domain/entities/nueva_solicitud.dart';
import '../bloc/crear_solicitud_cubit.dart';
import 'encabezado_paso.dart';

/// Paso 3: ¿dónde es el servicio? Una dirección guardada o una nueva.
class PasoUbicacion extends StatelessWidget {
  const PasoUbicacion({
    super.key,
    required this.direccion,
    required this.busquedaZona,
    required this.onBuscarZona,
  });

  final TextEditingController direccion;
  final TextEditingController busquedaZona;
  final ValueChanged<String> onBuscarZona;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CrearSolicitudCubit>().state;
    final cubit = context.read<CrearSolicitudCubit>();
    final nueva = state.modo == ModoUbicacion.nuevaDireccion;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EncabezadoPaso(
          titulo: '¿Dónde es el servicio?',
          subtitulo:
              'Los aliados solo ven el barrio. La dirección exacta la recibe '
              'únicamente el aliado que tome tu solicitud.',
        ),
        const SizedBox(height: 16),
        for (final s in state.catalogo.sitios) ...[
          _Opcion(
            clave: ValueKey('sitio-${s.id}'),
            seleccionada: !nueva && state.sitioId == s.id,
            icono: Icons.home_outlined,
            titulo: s.direccion,
            subtitulo: s.ubicacion,
            onTap: () => cubit.elegirSitio(s.id),
          ),
          const SizedBox(height: 10),
        ],
        _Opcion(
          clave: const ValueKey('opcion-nueva-direccion'),
          seleccionada: nueva,
          icono: Icons.add_location_alt_outlined,
          titulo: state.catalogo.sitios.isEmpty
              ? 'Dirección del servicio'
              : 'Usar otra dirección',
          subtitulo: 'Escribe la dirección y elige el barrio',
          onTap: cubit.usarNuevaDireccion,
        ),
        if (nueva) ...[
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('campo-direccion'),
            controller: direccion,
            onChanged: cubit.actualizarDireccion,
            maxLength: NuevaDireccion.maximo,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontWeight: FontWeight.w600),
            decoration: _decoracion(
              etiqueta: 'Dirección',
              hint: 'Ej: Calle Colima 120, Apto 401',
              icono: Icons.signpost_outlined,
            ),
          ),
          const SizedBox(height: 4),
          if (state.zona != null)
            _ZonaElegida(
              etiqueta: state.zona!.etiqueta,
              onCambiar: () {
                busquedaZona.clear();
                cubit.quitarZona();
              },
            )
          else ...[
            TextField(
              key: const ValueKey('campo-buscar-zona'),
              controller: busquedaZona,
              onChanged: onBuscarZona,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontWeight: FontWeight.w600),
              decoration: _decoracion(
                etiqueta: 'Barrio o localidad',
                hint: 'Escribe al menos 2 letras',
                icono: Icons.search_rounded,
              ),
            ),
            const SizedBox(height: 8),
            if (state.buscandoZonas)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppTheme.dark,
                    ),
                  ),
                ),
              )
            else if (state.zonasEncontradas.isNotEmpty)
              // Material propio: los ListTile pintan ahí su efecto de toque.
              Material(
                color: AppTheme.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                  side: const BorderSide(color: AppTheme.dark, width: 1.5),
                ),
                child: Column(
                  children: [
                    for (final z in state.zonasEncontradas)
                      ListTile(
                        key: ValueKey('zona-${z.id}'),
                        dense: true,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(
                          z.nombre,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: z.zonaPadre == null
                            ? null
                            : Text(z.zonaPadre!),
                        onTap: () => cubit.elegirZona(z),
                      ),
                  ],
                ),
              )
            else if (busquedaZona.text.trim().length >= 2)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'No encontramos ese barrio. Prueba con otro nombre.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
          ],
        ],
      ],
    );
  }

  static InputDecoration _decoracion({
    required String etiqueta,
    required String hint,
    required IconData icono,
  }) {
    OutlineInputBorder borde(double ancho) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      borderSide: BorderSide(color: AppTheme.dark, width: ancho),
    );
    return InputDecoration(
      labelText: etiqueta,
      hintText: hint,
      prefixIcon: Icon(icono, color: AppTheme.dark),
      filled: true,
      fillColor: AppTheme.surface,
      enabledBorder: borde(2),
      focusedBorder: borde(2.5),
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.clave,
    required this.seleccionada,
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  final Key clave;
  final bool seleccionada;
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radio = BorderRadius.circular(AppTheme.radiusXl);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: seleccionada,
      button: true,
      label: '$titulo, $subtitulo',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: seleccionada ? const Color(0xFFFEF9C3) : AppTheme.surface,
          borderRadius: radio,
          border: Border.all(
            color: AppTheme.dark,
            width: seleccionada ? 2.5 : 1.5,
          ),
          boxShadow: [if (seleccionada) AppTheme.hardShadowSm],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: clave,
            borderRadius: radio,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(icono, color: AppTheme.dark),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          subtitulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    seleccionada
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: AppTheme.dark,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZonaElegida extends StatelessWidget {
  const _ZonaElegida({required this.etiqueta, required this.onCambiar});

  final String etiqueta;
  final VoidCallback onCambiar;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('zona-elegida'),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.dark, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.place_rounded, color: AppTheme.dark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              etiqueta,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            key: const ValueKey('btn-cambiar-zona'),
            onPressed: onCambiar,
            child: const Text(
              'Cambiar',
              style: TextStyle(
                color: AppTheme.dark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
