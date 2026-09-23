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
}
