import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Archivo elegido por el usuario, ya leído en memoria.
class ArchivoLocal {
  const ArchivoLocal({required this.nombre, required this.bytes});

  final String nombre;
  final Uint8List bytes;
}

/// Puerto para elegir fotos del dispositivo. Se abstrae para que la
/// presentación sea testeable sin plugins nativos.
abstract interface class SelectorFotos {
  /// Devuelve las imágenes elegidas o una lista vacía si el usuario cancela.
  Future<List<ArchivoLocal>> seleccionar();
}

class FilePickerSelectorFotos implements SelectorFotos {
  const FilePickerSelectorFotos();

  static const extensiones = ['jpg', 'jpeg', 'png', 'webp'];

  @override
  Future<List<ArchivoLocal>> seleccionar() async {
    final archivos = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensiones,
    );
    return [
      for (final f in archivos)
        ArchivoLocal(nombre: f.name, bytes: await f.readAsBytes()),
    ];
  }
}
