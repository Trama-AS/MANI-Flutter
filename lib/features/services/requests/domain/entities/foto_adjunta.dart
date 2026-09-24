import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../failures/solicitud_failure.dart';

/// Foto del problema, validada antes de subirla.
class FotoAdjunta extends Equatable {
  const FotoAdjunta._(this.nombre, this.bytes, this.extension);

  static const int maxBytes = 5 * 1024 * 1024;
  static const formatos = {'jpg', 'jpeg', 'png', 'webp'};

  /// Lanza [SolicitudFailure] si el formato no es de imagen o pesa más de 5 MB.
  factory FotoAdjunta.crear({
    required String nombre,
    required Uint8List bytes,
  }) {
    final punto = nombre.lastIndexOf('.');
    final ext = punto < 0 ? '' : nombre.substring(punto + 1).toLowerCase();
    if (!formatos.contains(ext)) {
      throw const SolicitudFailure(SolicitudErrorTipo.fotoFormatoInvalido);
    }
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const SolicitudFailure(SolicitudErrorTipo.fotoMuyPesada);
    }
    return FotoAdjunta._(nombre, bytes, ext == 'jpeg' ? 'jpg' : ext);
  }

  final String nombre;
  final Uint8List bytes;

  /// Normalizada: jpg, png o webp.
  final String extension;

  String get mime => switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };

  /// Las fotos se comparan por nombre y tamaño (no byte a byte).
  @override
  List<Object?> get props => [nombre, bytes.length];
}
