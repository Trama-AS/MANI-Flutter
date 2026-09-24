import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mani/core/theme/app_theme.dart';

import '../../domain/entities/nueva_solicitud.dart';
import '../bloc/crear_solicitud_cubit.dart';
import 'encabezado_paso.dart';

/// Paso 2: describe el problema y adjunta fotos.
class PasoDetalle extends StatelessWidget {
  const PasoDetalle({
    super.key,
    required this.descripcion,
    required this.onAgregarFotos,
  });

  final TextEditingController descripcion;
  final VoidCallback onAgregarFotos;

  static const _consejos = [
    '¿Qué está pasando? (ej. gotea la llave del lavamanos)',
    '¿Desde cuándo ocurre?',
    '¿Dónde exactamente? (baño, cocina, fachada…)',
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CrearSolicitudCubit>().state;
    final cubit = context.read<CrearSolicitudCubit>();
    final largo = state.descripcion.trim().length;
    final falta = NuevaSolicitud.descripcionMinima - largo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncabezadoPaso(
          titulo: 'Cuéntanos el problema',
          subtitulo: state.categoria == null
              ? 'Entre más detalle, mejores cotizaciones recibirás.'
              : '${state.categoria!.nombre}: entre más detalle, mejores '
                    'cotizaciones recibirás.',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF9C3),
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            border: Border.all(color: AppTheme.dark, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Una buena descripción responde:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              for (final c in _consejos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  ', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Text(c, style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('campo-descripcion'),
          controller: descripcion,
          onChanged: cubit.actualizarDescripcion,
          minLines: 5,
          maxLines: 8,
          maxLength: NuevaSolicitud.descripcionMaxima,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText:
                'Ej: La tubería debajo del lavaplatos gotea desde ayer y el '
                'piso de la cocina se está mojando.',
            helperText: falta > 0
                ? 'Escribe al menos $falta caracteres más.'
                : '¡Bien! Tu descripción está completa.',
            helperStyle: TextStyle(
              color: falta > 0
                  ? AppTheme.textSecondary
                  : const Color(0xFF15803D),
              fontWeight: FontWeight.w700,
            ),
            filled: true,
            fillColor: AppTheme.surface,
            enabledBorder: _borde(2),
            focusedBorder: _borde(2.5),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Fotos del problema (opcional)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '${state.fotos.length}/${NuevaSolicitud.maxFotos}',
              key: const ValueKey('contador-fotos'),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Ayudan a que el aliado cotice sin visitar primero. JPG, PNG o WEBP '
          'de hasta 5 MB.',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < state.fotos.length; i++)
              _Miniatura(
                key: ValueKey('foto-$i'),
                indice: i,
                bytes: state.fotos[i].bytes,
                onQuitar: () => cubit.quitarFoto(i),
              ),
            if (!state.fotosCompletas) _AgregarFoto(onTap: onAgregarFotos),
          ],
        ),
      ],
    );
  }

  static OutlineInputBorder _borde(double ancho) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusXl),
    borderSide: BorderSide(color: AppTheme.dark, width: ancho),
  );
}

class _AgregarFoto extends StatelessWidget {
  const _AgregarFoto({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Agregar fotos',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('btn-agregar-fotos'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            border: Border.all(color: AppTheme.dark, width: 2),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined, color: AppTheme.dark),
              SizedBox(height: 4),
              Text(
                'Agregar',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Miniatura extends StatelessWidget {
  const _Miniatura({
    super.key,
    required this.indice,
    required this.bytes,
    required this.onQuitar,
  });

  final int indice;
  final Uint8List bytes;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                border: Border.all(color: AppTheme.dark, width: 2),
              ),
              child: Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(
                    Icons.image_outlined,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: Semantics(
              button: true,
              label: 'Quitar foto ${indice + 1}',
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('quitar-foto-$indice'),
                onTap: onQuitar,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppTheme.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.dark, width: 2),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
