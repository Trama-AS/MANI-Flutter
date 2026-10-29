import 'package:file_picker/file_picker.dart';
import 'package:mani/core/platform/selector_fotos.dart';

/// Puerto para elegir UN documento (PDF o imagen) del dispositivo. Se abstrae
/// para que la presentación sea testeable sin plugins nativos.
abstract interface class SelectorDocumento {
  /// Devuelve el archivo elegido o `null` si el usuario cancela.
  Future<ArchivoLocal?> seleccionar();
}

class FilePickerSelectorDocumento implements SelectorDocumento {
  const FilePickerSelectorDocumento();

  static const extensiones = ['pdf', 'jpg', 'jpeg', 'png'];

  @override
  Future<ArchivoLocal?> seleccionar() async {
    final archivos = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensiones,
    );
    if (archivos.isEmpty) return null;
    final f = archivos.first;
    return ArchivoLocal(nombre: f.name, bytes: await f.readAsBytes());
  }
}
