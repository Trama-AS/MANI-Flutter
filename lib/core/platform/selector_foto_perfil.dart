import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Abre el explorador nativo para elegir la foto de perfil (SCRUM-1389).
/// Cumple `SelectorArchivoImagen`: devuelve `null` si el usuario cancela.
///
/// El filtro de extensiones solo orienta al usuario; la regla (JPG o PNG de
/// hasta 5 MB) la sigue aplicando `GatewayPerfilPropioDataSource.esFotoValida`.
Future<({String nombre, Uint8List bytes})?> seleccionarFotoPerfil({
  Future<PlatformFile?> Function({
    FileType type,
    List<String>? allowedExtensions,
  })?
  pickFile,
}) async {
  final picker = pickFile ?? FilePicker.pickFile;
  final archivo = await picker(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png'],
  );
  if (archivo == null) return null;
  return (nombre: archivo.name, bytes: await archivo.readAsBytes());
}
