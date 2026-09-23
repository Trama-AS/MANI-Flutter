import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/services/requests/domain/entities/nueva_solicitud.dart';
import 'package:mani/features/services/requests/domain/failures/solicitud_failure.dart';
import 'package:mani/features/services/requests/presentation/bloc/crear_solicitud_cubit.dart';

import '../fakes.dart';

void main() {
  late FakeSolicitudesClienteRepository repo;
  late CrearSolicitudCubit cubit;

  setUp(() {
    repo = FakeSolicitudesClienteRepository();
    cubit = crearCubit(repo);
  });

  tearDown(() => cubit.close());

  /// Deja el formulario completo con un sitio guardado.
  Future<void> completar() async {
    await cubit.cargar();
    cubit
      ..elegirCategoria(plomeria.id)
      ..actualizarDescripcion(descripcionValida)
      ..siguiente()
      ..siguiente();
  }

  group('cargar', () {
    test('con direcciones guardadas propone la más reciente', () async {
      await cubit.cargar();
      expect(cubit.state.carga, CargaFormulario.listo);
      expect(cubit.state.modo, ModoUbicacion.sitioGuardado);
      expect(cubit.state.sitioId, casa.id);
    });

    test('sin direcciones guardadas pide una nueva', () async {
      repo.sitios = const [];
      await cubit.cargar();
      expect(cubit.state.modo, ModoUbicacion.nuevaDireccion);
      expect(cubit.state.sitioId, isNull);
    });

    test('un error de carga deja la pantalla en error', () async {
      repo.fallarAlCargar = const SolicitudFailure(
        SolicitudErrorTipo.noEsCliente,
      );
      await cubit.cargar();
      expect(cubit.state.carga, CargaFormulario.error);
      expect(cubit.state.error?.tipo, SolicitudErrorTipo.noEsCliente);
    });
  });

  group('navegación del asistente', () {
    setUp(() => cubit.cargar());

    test('elegir la categoría avanza sola al paso del problema', () {
      cubit.elegirCategoria(plomeria.id);
      expect(cubit.state.paso, PasoSolicitud.detalle);
      expect(cubit.state.categoria, plomeria);
    });

    test('no avanza sin una descripción válida', () {
      cubit
        ..elegirCategoria(plomeria.id)
        ..actualizarDescripcion('Gotea')
        ..siguiente();
      expect(cubit.state.paso, PasoSolicitud.detalle);
      expect(cubit.state.puedeAvanzar, isFalse);

      cubit
        ..actualizarDescripcion(descripcionValida)
        ..siguiente();
      expect(cubit.state.paso, PasoSolicitud.ubicacion);
    });

    test('anterior retrocede e irA solo salta hacia atrás', () {
      cubit
        ..elegirCategoria(plomeria.id)
        ..actualizarDescripcion(descripcionValida)
        ..siguiente()
        ..siguiente();
      expect(cubit.state.paso, PasoSolicitud.revision);

      cubit.irA(PasoSolicitud.detalle);
      expect(cubit.state.paso, PasoSolicitud.detalle);
      cubit.irA(PasoSolicitud.revision);
      expect(
        cubit.state.paso,
        PasoSolicitud.detalle,
        reason: 'no salta adelante',
      );
      cubit.anterior();
      expect(cubit.state.paso, PasoSolicitud.categoria);
    });
  });

  group('fotos', () {
    setUp(() => cubit.cargar());

    test('agrega las válidas e informa las rechazadas', () {
      cubit.agregarFotos([foto('a.jpg'), foto('contrato.pdf'), foto('b.png')]);

      expect(cubit.state.fotos.map((f) => f.nombre), ['a.jpg', 'b.png']);
      expect(cubit.state.aviso?.esError, isTrue);
      expect(cubit.state.aviso?.mensaje, contains('JPG, PNG o WEBP'));
    });

    test('no pasa de 5 fotos', () {
      cubit.agregarFotos(List.generate(7, (i) => foto('f$i.jpg')));

      expect(cubit.state.fotos, hasLength(NuevaSolicitud.maxFotos));
      expect(cubit.state.fotosCompletas, isTrue);
      expect(cubit.state.aviso?.mensaje, contains('2 fotos no se agregaron'));
    });

    test('rechaza fotos de más de 5 MB', () {
      cubit.agregarFotos([foto('grande.jpg', bytes: 6 * 1024 * 1024)]);
      expect(cubit.state.fotos, isEmpty);
      expect(cubit.state.aviso?.mensaje, contains('5 MB'));
    });

    test('quitarFoto elimina la indicada', () {
      cubit
        ..agregarFotos([foto('a.jpg'), foto('b.jpg')])
        ..quitarFoto(0);
      expect(cubit.state.fotos.single.nombre, 'b.jpg');
    });
  });

  group('ubicación', () {
    setUp(() => cubit.cargar());

    test('una dirección nueva exige dirección y barrio', () async {
      cubit
        ..usarNuevaDireccion()
        ..actualizarDireccion('Calle Durango 45');
      expect(cubit.state.ubicacionValida, isFalse);

      await cubit.buscarZonas('rom');
      expect(cubit.state.zonasEncontradas, [romaNorte]);
      cubit.elegirZona(romaNorte);

      expect(cubit.state.zona, romaNorte);
      expect(cubit.state.zonasEncontradas, isEmpty);
      expect(cubit.state.ubicacionValida, isTrue);
    });

    test(
      'buscar con menos de 2 letras limpia resultados sin consultar',
      () async {
        await cubit.buscarZonas('r');
        expect(cubit.state.zonasEncontradas, isEmpty);
        expect(repo.llamadasBuscar, 0);
      },
    );
  });

  group('publicar', () {
    test(
      'publica con la clave del formulario y muestra el resultado',
      () async {
        await completar();

        final ok = await cubit.publicar();

        expect(ok, isTrue);
        expect(cubit.state.publicada?.categoria, 'Plomería');
        final enviada = repo.publicadas.single;
        expect(enviada.claveIdempotencia, cubit.state.clave);
        expect(enviada.ubicacion, const SitioExistente(casa));
      },
    );

    test(
      'ante un error conserva todo y reintenta con la MISMA clave',
      () async {
        await completar();
        cubit.agregarFotos([foto('a.jpg')]);
        repo.fallarAlPublicar = const SolicitudFailure(
          SolicitudErrorTipo.sinConexion,
        );

        expect(await cubit.publicar(), isFalse);
        expect(cubit.state.errorEnvio?.tipo, SolicitudErrorTipo.sinConexion);
        expect(cubit.state.descripcion, descripcionValida);
        expect(cubit.state.fotos, hasLength(1));
        final clave = cubit.state.clave;

        repo.fallarAlPublicar = null;
        expect(await cubit.publicar(), isTrue);
        expect(repo.publicadas.single.claveIdempotencia, clave);
      },
    );

    test('ignora un doble toque mientras publica', () async {
      await completar();
      repo.pausaPublicar = Completer<void>();

      final primera = cubit.publicar();
      expect(cubit.state.publicando, isTrue);
      expect(await cubit.publicar(), isFalse);

      repo.pausaPublicar!.complete();
      expect(await primera, isTrue);
      expect(repo.llamadasPublicar, 1);
    });

    test('un error de zona lleva al paso de ubicación', () async {
      await completar();
      repo.fallarAlPublicar = const SolicitudFailure(
        SolicitudErrorTipo.zonaInvalida,
      );

      await cubit.publicar();

      expect(cubit.state.paso, PasoSolicitud.ubicacion);
    });

    test('nuevaSolicitud reinicia el formulario con otra clave', () async {
      await completar();
      await cubit.publicar();
      final claveAnterior = cubit.state.clave;

      await cubit.nuevaSolicitud();

      expect(cubit.state.publicada, isNull);
      expect(cubit.state.paso, PasoSolicitud.categoria);
      expect(cubit.state.descripcion, isEmpty);
      expect(cubit.state.clave, isNot(claveAnterior));
      expect(cubit.state.carga, CargaFormulario.listo);
    });
  });
}
