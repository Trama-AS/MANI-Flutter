import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/utils/generador_id.dart';
import 'package:mani/features/services/requests/domain/entities/catalogo_solicitud.dart';
import 'package:mani/features/services/requests/domain/entities/foto_adjunta.dart';
import 'package:mani/features/services/requests/domain/entities/nueva_solicitud.dart';
import 'package:mani/features/services/requests/domain/failures/solicitud_failure.dart';
import 'package:mani/features/services/requests/domain/usecases/solicitud_usecases.dart';

import '../fakes.dart';

Matcher _falla(SolicitudErrorTipo tipo) =>
    throwsA(isA<SolicitudFailure>().having((f) => f.tipo, 'tipo', tipo));

NuevaSolicitud _nueva({
  CategoriaDisponible? categoria = plomeria,
  String descripcion = descripcionValida,
  List<FotoAdjunta> fotos = const [],
  UbicacionSolicitud ubicacion = const SitioExistente(casa),
}) => NuevaSolicitud.crear(
  categoria: categoria,
  descripcion: descripcion,
  fotos: fotos,
  ubicacion: ubicacion,
  claveIdempotencia: 'clave-1',
);

void main() {
  group('FotoAdjunta', () {
    test('acepta JPG, JPEG, PNG y WEBP y normaliza la extensión', () {
      final jpeg = FotoAdjunta.crear(nombre: 'Fuga.JPEG', bytes: pngMinimo);
      expect(jpeg.extension, 'jpg');
      expect(jpeg.mime, 'image/jpeg');
      expect(
        FotoAdjunta.crear(nombre: 'a.png', bytes: pngMinimo).mime,
        'image/png',
      );
      expect(
        FotoAdjunta.crear(nombre: 'a.webp', bytes: pngMinimo).mime,
        'image/webp',
      );
    });

    test('rechaza formatos que no son imagen', () {
      expect(
        () => FotoAdjunta.crear(nombre: 'contrato.pdf', bytes: pngMinimo),
        _falla(SolicitudErrorTipo.fotoFormatoInvalido),
      );
      expect(
        () => FotoAdjunta.crear(nombre: 'sin_extension', bytes: pngMinimo),
        _falla(SolicitudErrorTipo.fotoFormatoInvalido),
      );
    });

    test('rechaza fotos vacías o de más de 5 MB', () {
      expect(
        () => FotoAdjunta.crear(nombre: 'a.jpg', bytes: Uint8List(0)),
        _falla(SolicitudErrorTipo.fotoMuyPesada),
      );
      expect(
        () => FotoAdjunta.crear(
          nombre: 'a.jpg',
          bytes: Uint8List(FotoAdjunta.maxBytes + 1),
        ),
        _falla(SolicitudErrorTipo.fotoMuyPesada),
      );
      expect(
        FotoAdjunta.crear(
          nombre: 'a.jpg',
          bytes: Uint8List(FotoAdjunta.maxBytes),
        ).bytes.length,
        FotoAdjunta.maxBytes,
      );
    });
  });

  group('NuevaDireccion', () {
    test('normaliza espacios y exige 5 a 200 caracteres', () {
      final d = NuevaDireccion.crear(
        direccion: '  Calle   Colima 120 ',
        zona: romaNorte,
      );
      expect(d.direccion, 'Calle Colima 120');
      expect(
        () => NuevaDireccion.crear(direccion: 'Cll', zona: romaNorte),
        _falla(SolicitudErrorTipo.ubicacionInvalida),
      );
      expect(
        () => NuevaDireccion.crear(direccion: 'x' * 201, zona: romaNorte),
        _falla(SolicitudErrorTipo.ubicacionInvalida),
      );
    });

    test('exige elegir el barrio', () {
      expect(
        () => NuevaDireccion.crear(direccion: 'Calle Colima 120', zona: null),
        _falla(SolicitudErrorTipo.zonaInvalida),
      );
    });
  });

  group('NuevaSolicitud', () {
    test('se crea con la descripción recortada', () {
      final n = _nueva(descripcion: '   $descripcionValida   ');
      expect(n.descripcion, descripcionValida);
      expect(n.claveIdempotencia, 'clave-1');
    });

    test('exige categoría', () {
      expect(
        () => _nueva(categoria: null),
        _falla(SolicitudErrorTipo.categoriaInvalida),
      );
    });

    test('exige una descripción de 20 a 1000 caracteres', () {
      expect(
        () => _nueva(descripcion: 'Gotea la llave'),
        _falla(SolicitudErrorTipo.descripcionInvalida),
      );
      expect(
        () => _nueva(descripcion: 'x' * 1001),
        _falla(SolicitudErrorTipo.descripcionInvalida),
      );
      expect(NuevaSolicitud.descripcionValida('x' * 20), isTrue);
      expect(NuevaSolicitud.descripcionValida('   ${'x' * 19}   '), isFalse);
    });

    test('admite hasta 5 fotos', () {
      final f = FotoAdjunta.crear(nombre: 'a.png', bytes: pngMinimo);
      expect(_nueva(fotos: List.filled(5, f)).fotos, hasLength(5));
      expect(
        () => _nueva(fotos: List.filled(6, f)),
        _falla(SolicitudErrorTipo.demasiadasFotos),
      );
    });
  });

  test('ModalidadCobro usa los códigos de flujo operativo de US-03.1.1', () {
    expect(
      ModalidadCobro.desde('COTIZACION_PREVIA'),
      ModalidadCobro.cotizacionPrevia,
    );
    expect(
      ModalidadCobro.desde('tarifa_estandar'),
      ModalidadCobro.tarifaEstandar,
    );
    expect(ModalidadCobro.desde(null), ModalidadCobro.desconocida);
  });

  test('ubicaciones y zonas legibles', () {
    expect(casa.ubicacion, 'Roma Norte · Cuauhtémoc');
    expect(romaNorte.etiqueta, 'Roma Norte · Cuauhtémoc');
    expect(const ZonaOpcion(id: 'x', nombre: 'Centro').etiqueta, 'Centro');
  });

  group('Casos de uso', () {
    test('CargarCatalogoSolicitud trae categorías y sitios', () async {
      final c = await CargarCatalogoSolicitud(
        FakeSolicitudesClienteRepository(),
      )();
      expect(c.categorias, [plomeria, cerrajeria]);
      expect(c.sitios, [casa]);
    });

    test('BuscarZonas no consulta con menos de 2 caracteres', () async {
      final repo = FakeSolicitudesClienteRepository();
      expect(await BuscarZonas(repo)(' r '), isEmpty);
      expect(repo.llamadasBuscar, 0);
      expect(await BuscarZonas(repo)('ro'), [romaNorte]);
    });

    test('PublicarSolicitud delega en el repositorio', () async {
      final repo = FakeSolicitudesClienteRepository();
      final p = await PublicarSolicitud(repo)(_nueva());
      expect(p.categoria, 'Plomería');
      expect(repo.publicadas, hasLength(1));
    });
  });

  test('nuevoUuid genera UUID v4 válidos y distintos', () {
    final formato = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final ids = {for (var i = 0; i < 200; i++) nuevoUuid()};
    expect(ids, hasLength(200));
    expect(ids.every(formato.hasMatch), isTrue);
  });

  test('cada tipo de falla tiene un mensaje para el usuario', () {
    for (final t in SolicitudErrorTipo.values) {
      expect(SolicitudFailure(t).mensajeUsuario, isNotEmpty, reason: t.name);
    }
  });
}
