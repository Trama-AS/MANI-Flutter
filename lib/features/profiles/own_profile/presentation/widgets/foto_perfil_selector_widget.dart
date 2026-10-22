import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mani/features/profiles/own_profile/data/datasources/perfil_propio_remote_datasource.dart';

typedef SelectorArchivoImagen =
    Future<({String nombre, Uint8List bytes})?> Function();

/// SCRUM-1030: Componente para cambiar y subir una nueva foto de perfil.
class FotoPerfilSelectorWidget extends StatelessWidget {
  const FotoPerfilSelectorWidget({
    super.key,
    required this.fullName,
    this.photoUrl,
    this.subiendo = false,
    required this.onFotoSeleccionada,
    this.selectorImagen,
  });

  final String fullName;
  final String? photoUrl;
  final bool subiendo;
  final Future<void> Function(String nombreArchivo, Uint8List bytes)
  onFotoSeleccionada;
  final SelectorArchivoImagen? selectorImagen;

  String get _iniciales {
    final partes = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2);
    if (partes.isEmpty) return 'U';
    return partes.map((p) => p[0].toUpperCase()).join();
  }

  Future<void> _seleccionar(BuildContext context) async {
    if (selectorImagen == null) return;
    final archivo = await selectorImagen!();
    if (archivo == null) return;
    if (!GatewayPerfilPropioDataSource.esFormatoImagenSoportado(
      archivo.nombre,
    )) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            key: Key('snackbar-error-formato-foto'),
            content: Text(
              'Formato de imagen no soportado. Usa PNG, JPG, JPEG o WEBP.',
            ),
          ),
        );
      }
      return;
    }
    await onFotoSeleccionada(archivo.nombre, archivo.bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          key: const Key('avatar-perfil-propio'),
          radius: 42,
          child: Text(
            _iniciales,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
        if (photoUrl != null && photoUrl!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            photoUrl!,
            key: const Key('texto-foto-actual'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('btn-cambiar-foto-perfil'),
          onPressed: subiendo ? null : () => _seleccionar(context),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(subiendo ? 'Subiendo foto...' : 'Cambiar foto de perfil'),
        ),
      ],
    );
  }
}
