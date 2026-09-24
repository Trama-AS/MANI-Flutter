import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/theme/app_theme.dart';

import '../bloc/crear_solicitud_cubit.dart';
import '../utils/estilo_solicitud.dart';
import 'encabezado_paso.dart';

/// Paso 4: revisar antes de publicar, con acceso directo a editar cada parte.
class PasoRevision extends StatelessWidget {
  const PasoRevision({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CrearSolicitudCubit>().state;
    final cubit = context.read<CrearSolicitudCubit>();
    final categoria = state.categoria;
    final ubicacion = switch (state.modo) {
      ModoUbicacion.sitioGuardado => (
        state.sitio?.direccion ?? '',
        state.sitio?.ubicacion ?? '',
      ),
      ModoUbicacion.nuevaDireccion => (
        state.direccion.trim(),
        state.zona?.etiqueta ?? '',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EncabezadoPaso(
          titulo: 'Revisa y publica',
          subtitulo: 'Así verán tu solicitud los aliados de tu zona.',
        ),
        const SizedBox(height: 16),
        _Seccion(
          titulo: 'Servicio',
          onEditar: () => cubit.irA(PasoSolicitud.categoria),
          claveEditar: 'editar-categoria',
          child: Row(
            children: [
              Icon(
                iconoCategoria(categoria?.nombre ?? ''),
                color: AppTheme.dark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      categoria?.nombre ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (categoria != null)
                      Text(
                        textoModalidad(categoria.modalidad),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Seccion(
          titulo: 'Problema',
          onEditar: () => cubit.irA(PasoSolicitud.detalle),
          claveEditar: 'editar-detalle',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(state.descripcion.trim()),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.photo_library_outlined,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    switch (state.fotos.length) {
                      0 => 'Sin fotos',
                      1 => '1 foto',
                      final n => '$n fotos',
                    },
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Seccion(
          titulo: 'Ubicación',
          onEditar: () => cubit.irA(PasoSolicitud.ubicacion),
          claveEditar: 'editar-ubicacion',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ubicacion.$1,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                ubicacion.$2,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _QuePasaDespues(),
      ],
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({
    required this.titulo,
    required this.onEditar,
    required this.claveEditar,
    required this.child,
  });

  final String titulo;
  final VoidCallback onEditar;
  final String claveEditar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.dark, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ),
              TextButton.icon(
                key: ValueKey(claveEditar),
                onPressed: onEditar,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Editar'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.dark,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          Padding(padding: const EdgeInsets.only(right: 8), child: child),
        ],
      ),
    );
  }
}

class _QuePasaDespues extends StatelessWidget {
  const _QuePasaDespues();

  static const _pasos = [
    'Los aliados verificados de este servicio en tu zona ven tu solicitud.',
    'El primero que la acepte se queda con el trabajo y te contactará.',
    'Recibirás su cotización antes de que empiece.',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF9C3),
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.dark, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Qué pasa después?',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _pasos.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppTheme.dark,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _pasos[i],
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
