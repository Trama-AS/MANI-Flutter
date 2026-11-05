import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Puerto para guardar un archivo en el dispositivo (en web, lo descarga). Se
/// abstrae para que la presentación sea testeable sin plugins nativos.
abstract interface class GuardadorArchivo {
  /// `true` si se guardó; `false` si la persona canceló.
  Future<bool> guardar({
    required String nombre,
    required Uint8List bytes,
    String tipoMime = 'application/octet-stream',
  });
}

class FilePickerGuardadorArchivo implements GuardadorArchivo {
  const FilePickerGuardadorArchivo();

  @override
  Future<bool> guardar({
    required String nombre,
    required Uint8List bytes,
    String tipoMime = 'application/octet-stream',
  }) async {
    final destino = await FilePicker.saveFile(
      fileName: nombre,
      bytes: bytes,
      mimeType: tipoMime,
    );
    return destino != null;
  }
}
