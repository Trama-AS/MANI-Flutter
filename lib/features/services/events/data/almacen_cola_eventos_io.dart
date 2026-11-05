import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:mani/features/services/requests/domain/entities/foto_adjunta.dart';

import 'cola_eventos.dart';
import 'eventos_datasource.dart';

AlmacenColaEventos crearAlmacen() => AlmacenColaEnArchivos(
  disponible: Platform.isAndroid || Platform.isIOS,
  directorio: () async => Directory(
    '${(await getApplicationSupportDirectory()).path}/cola_eventos',
  ),
);

/// Cola en archivos privados de la app (US-04.3.6 / SCRUM-873): `cola.json`
/// con los datos de cada evento y la foto aparte, con la clave como nombre.
/// Cada escritura reemplaza el índice completo con un archivo temporal y
/// `rename`, así un cierre a mitad de camino no lo deja corrupto.
class AlmacenColaEnArchivos implements AlmacenColaEventos {
  AlmacenColaEnArchivos({
    required this.disponible,
    required Future<Directory> Function() directorio,
  }) : _directorio = directorio;

  @override
  final bool disponible;
  final Future<Directory> Function() _directorio;

  Future<Directory> _carpeta() async {
    final dir = await _directorio();
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _indice() async => File('${(await _carpeta()).path}/cola.json');

  Future<List<Map<String, dynamic>>> _leerIndice() async {
    final f = await _indice();
    if (!f.existsSync()) return [];
    try {
      final datos = jsonDecode(await f.readAsString());
      return [
        if (datos is List)
          for (final e in datos)
            if (e is Map) Map<String, dynamic>.from(e),
      ];
    } on FormatException {
      return [];
    }
  }

  Future<void> _escribirIndice(List<Map<String, dynamic>> filas) async {
    final f = await _indice();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(filas), flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<List<EventoPendiente>> leer() async {
    final dir = await _carpeta();
    final eventos = <EventoPendiente>[];
    for (final fila in await _leerIndice()) {
      final evento = await _desdeFila(dir, fila);
      if (evento != null) eventos.add(evento);
    }
    return eventos;
  }

  /// Una fila incompleta o sin su foto se omite: mejor no enviarla que
  /// enviar un evento distinto al que tomó el aliado.
  Future<EventoPendiente?> _desdeFila(
    Directory dir,
    Map<String, dynamic> fila,
  ) async {
    final tipo = TipoEventoAliado.values
        .where((t) => t.valor == fila['tipo'])
        .firstOrNull;
    final ocurridoEn = DateTime.tryParse('${fila['ocurridoEn']}');
    if (tipo == null || ocurridoEn == null) return null;
    FotoAdjunta? foto;
    final nombreFoto = fila['foto'];
    if (nombreFoto is String) {
      final archivo = File('${dir.path}/${fila['clave']}.foto');
      if (!archivo.existsSync()) return null;
      foto = FotoAdjunta.crear(
        nombre: nombreFoto,
        bytes: await archivo.readAsBytes(),
      );
    }
    return EventoPendiente(
      clave: '${fila['clave']}',
      usuarioId: '${fila['usuarioId']}',
      solicitudId: '${fila['solicitudId']}',
      tipo: tipo,
      observacion: '${fila['observacion']}',
      ocurridoEn: ocurridoEn,
      foto: foto,
    );
  }

  @override
  Future<void> agregar(EventoPendiente evento) async {
    final dir = await _carpeta();
    // La foto va primero: un índice que la nombra nunca queda sin ella.
    if (evento.foto != null) {
      await File(
        '${dir.path}/${evento.clave}.foto',
      ).writeAsBytes(evento.foto!.bytes, flush: true);
    }
    await _escribirIndice([
      ...await _leerIndice(),
      {
        'clave': evento.clave,
        'usuarioId': evento.usuarioId,
        'solicitudId': evento.solicitudId,
        'tipo': evento.tipo.valor,
        'observacion': evento.observacion,
        'ocurridoEn': evento.ocurridoEn.toUtc().toIso8601String(),
        if (evento.foto != null) 'foto': evento.foto!.nombre,
      },
    ]);
  }

  @override
  Future<void> quitar(String clave) async {
    final dir = await _carpeta();
    await _escribirIndice([
      for (final fila in await _leerIndice())
        if (fila['clave'] != clave) fila,
    ]);
    final foto = File('${dir.path}/$clave.foto');
    if (foto.existsSync()) await foto.delete();
  }

  @override
  Future<void> vaciar() async {
    final dir = await _directorio();
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
