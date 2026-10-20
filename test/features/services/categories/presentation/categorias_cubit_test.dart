import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/services/categories/domain/entities/flujo_operativo.dart';
import 'package:mani/features/services/categories/domain/failures/categoria_failure.dart';
import 'package:mani/features/services/categories/presentation/bloc/categorias_cubit.dart';

import '../fakes.dart';

void main() {
  late FakeCategoriasRepository repo;
  late CategoriasCubit cubit;

  setUp(() {
    repo = FakeCategoriasRepository([
      categoria('Plomería', aliados: 2),
      categoria(
        'Cerrajería',
        activa: false,
        flujo: FlujoOperativo.tarifaEstandar,
      ),
    ]);
    cubit = crearCubit(repo);
  });

  tearDown(() => cubit.close());

  group('cargar', () {
    test('queda listo con el catálogo ordenado y sus conteos', () async {
      await cubit.cargar();

      expect(cubit.state.carga, CargaCategorias.listo);
      expect(cubit.state.categorias.map((c) => c.nombre), [
        'Cerrajería',
        'Plomería',
      ]);
      expect(cubit.state.activas, 1);
      expect(cubit.state.ocultas, 1);
    });

    test('un error inicial deja la pantalla en estado error', () async {
      repo.fallarAlListar = const CategoriaFailure(
        CategoriaErrorTipo.noAutorizado,
      );

      await cubit.cargar();

      expect(cubit.state.carga, CargaCategorias.error);
      expect(cubit.state.error?.tipo, CategoriaErrorTipo.noAutorizado);
    });

    test('un error al refrescar conserva el catálogo y avisa', () async {
      await cubit.cargar();
      repo.fallarAlListar = const CategoriaFailure(
        CategoriaErrorTipo.sinConexion,
      );

      await cubit.cargar(silencioso: true);

      expect(cubit.state.carga, CargaCategorias.listo);
      expect(cubit.state.categorias, hasLength(2));
      expect(cubit.state.aviso?.esError, isTrue);
    });
  });

  test('buscar filtra por nombre', () async {
    await cubit.cargar();
    cubit.buscar('cerra');
    expect(cubit.state.visibles.map((c) => c.nombre), ['Cerrajería']);
  });

  group('crear', () {
    setUp(() => cubit.cargar());

    test('agrega la categoría en orden, la resalta y avisa', () async {
      final falla = await cubit.crear(
        nombre: ' Aire   acondicionado ',
        flujo: FlujoOperativo.cotizacionPrevia,
        activa: true,
      );

      expect(falla, isNull);
      expect(cubit.state.categorias.map((c) => c.nombre), [
        'Aire acondicionado',
        'Cerrajería',
        'Plomería',
      ]);
      final nueva = cubit.state.categorias.first;
      expect(cubit.state.recienCreadaId, nueva.id);
      expect(cubit.state.guardando, isFalse);
      expect(cubit.state.aviso?.mensaje, contains('Ya aparece en el catálogo'));
    });

    test('una categoría oculta avisa que los clientes no la verán', () async {
      await cubit.crear(
        nombre: 'Pintura',
        flujo: FlujoOperativo.tarifaEstandar,
        activa: false,
      );
      expect(cubit.state.aviso?.mensaje, contains('guardada como oculta'));
      expect(cubit.state.ocultas, 2);
    });

    test('datos inválidos devuelven la falla sin llamar al servidor', () async {
      final sinFlujo = await cubit.crear(
        nombre: 'Pintura',
        flujo: null,
        activa: true,
      );
      final nombreCorto = await cubit.crear(
        nombre: 'ab',
        flujo: FlujoOperativo.tarifaEstandar,
        activa: true,
      );

      expect(sinFlujo?.tipo, CategoriaErrorTipo.flujoInvalido);
      expect(nombreCorto?.tipo, CategoriaErrorTipo.nombreInvalido);
      expect(repo.llamadasCrear, 0);
    });

    test('un duplicado ya cargado se detecta sin llamar al servidor', () async {
      final falla = await cubit.crear(
        nombre: 'PLOMERÍA',
        flujo: FlujoOperativo.cotizacionPrevia,
        activa: true,
      );
      expect(falla?.tipo, CategoriaErrorTipo.nombreDuplicado);
      expect(repo.llamadasCrear, 0);
    });

    test('si otro admin la creó antes (409) recarga el catálogo', () async {
      repo.creadaPorOtroAdmin('Jardinería');

      final falla = await cubit.crear(
        nombre: 'Jardinería',
        flujo: FlujoOperativo.cotizacionPrevia,
        activa: true,
      );

      expect(falla?.tipo, CategoriaErrorTipo.nombreDuplicado);
      expect(
        cubit.state.categorias.map((c) => c.nombre),
        contains('Jardinería'),
      );
      expect(cubit.state.guardando, isFalse);
    });

    test('marca guardando e ignora un doble toque mientras guarda', () async {
      repo.pausaCrear = Completer<void>();

      final primera = cubit.crear(
        nombre: 'Pintura',
        flujo: FlujoOperativo.tarifaEstandar,
        activa: true,
      );
      expect(cubit.state.guardando, isTrue);
      await cubit.crear(
        nombre: 'Pintura',
        flujo: FlujoOperativo.tarifaEstandar,
        activa: true,
      );

      repo.pausaCrear!.complete();
      expect(await primera, isNull);
      expect(repo.llamadasCrear, 1);
    });

    test('un error de red se devuelve y no altera el catálogo', () async {
      repo.fallarAlCrear = const CategoriaFailure(
        CategoriaErrorTipo.sinConexion,
      );

      final falla = await cubit.crear(
        nombre: 'Pintura',
        flujo: FlujoOperativo.tarifaEstandar,
        activa: true,
      );

      expect(falla?.tipo, CategoriaErrorTipo.sinConexion);
      expect(cubit.state.categorias, hasLength(2));
      expect(cubit.state.guardando, isFalse);
    });
  });

  group('cambiarEstado (US-03.1.2)', () {
    setUp(() => cubit.cargar());

    test(
      'desactiva una categoría activa, actualiza conteos y avisa que los servicios en curso continúan',
      () async {
        final plomeria = cubit.state.categorias.firstWhere(
          (c) => c.nombre == 'Plomería',
        );

        final falla = await cubit.cambiarEstado(plomeria, activa: false);

        expect(falla, isNull);
        expect(cubit.state.activas, 0);
        expect(cubit.state.ocultas, 2);
        final actualizada = cubit.state.categorias.firstWhere(
          (c) => c.id == plomeria.id,
        );
        expect(actualizada.activa, isFalse);
        expect(actualizada.aliadosAsociados, 2);
        expect(
          cubit.state.aviso?.mensaje,
          contains('los servicios en curso continúan sin cambios'),
        );
      },
    );

    test('reactiva una categoría oculta y avisa al administrador', () async {
      final cerrajeria = cubit.state.categorias.firstWhere(
        (c) => c.nombre == 'Cerrajería',
      );

      final falla = await cubit.cambiarEstado(cerrajeria, activa: true);

      expect(falla, isNull);
      expect(cubit.state.activas, 2);
      expect(cubit.state.ocultas, 0);
      expect(
        cubit.state.aviso?.mensaje,
        contains('Ya vuelve a aparecer en el catálogo'),
      );
    });

    test(
      'marca cambiandoEstadoIds e ignora toques repetidos mientras espera',
      () async {
        repo.pausaCambiarEstado = Completer<void>();
        final plomeria = cubit.state.categorias.firstWhere(
          (c) => c.nombre == 'Plomería',
        );

        final primera = cubit.cambiarEstado(plomeria, activa: false);
        expect(cubit.state.cambiandoEstadoDe(plomeria.id), isTrue);

        await cubit.cambiarEstado(plomeria, activa: false);

        repo.pausaCambiarEstado!.complete();
        expect(await primera, isNull);
        expect(cubit.state.cambiandoEstadoDe(plomeria.id), isFalse);
        expect(repo.llamadasCambiarEstado, 1);
      },
    );

    test(
      'si la categoría ya no existe (404), recarga el catálogo y avisa el error',
      () async {
        final plomeria = cubit.state.categorias.firstWhere(
          (c) => c.nombre == 'Plomería',
        );
        repo.eliminarDeMemoria(plomeria.id);

        final falla = await cubit.cambiarEstado(plomeria, activa: false);

        expect(falla?.tipo, CategoriaErrorTipo.noEncontrada);
        expect(cubit.state.aviso?.esError, isTrue);
        expect(
          cubit.state.categorias.map((c) => c.nombre),
          isNot(contains('Plomería')),
        );
      },
    );
  });
}
