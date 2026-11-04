import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/platform/selector_foto_perfil.dart';

final class _MockPlatformFile extends PlatformFile {
  _MockPlatformFile({required this.name, required this.bytes});

  @override
  final String name;

  final Uint8List bytes;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('seleccionarFotoPerfil (SCRUM-1389)', () {
    test('devuelve null cuando el usuario cancela la selección', () async {
      FileType? tipoCapturado;
      List<String>? extensionesCapturadas;

      final resultado = await seleccionarFotoPerfil(
        pickFile: ({type = FileType.any, allowedExtensions}) async {
          tipoCapturado = type;
          extensionesCapturadas = allowedExtensions;
          return null;
        },
      );

      expect(resultado, isNull);
      expect(tipoCapturado, equals(FileType.custom));
      expect(extensionesCapturadas, equals(['jpg', 'jpeg', 'png']));
    });

    test('devuelve nombre y bytes cuando se selecciona un archivo', () async {
      final bytesPrueba = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final archivoMock = _MockPlatformFile(
        name: 'perfil.png',
        bytes: bytesPrueba,
      );

      final resultado = await seleccionarFotoPerfil(
        pickFile: ({type = FileType.any, allowedExtensions}) async {
          return archivoMock;
        },
      );

      expect(resultado, isNotNull);
      expect(resultado!.nombre, equals('perfil.png'));
      expect(resultado.bytes, equals(bytesPrueba));
    });
  });
}
