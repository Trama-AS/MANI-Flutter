import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/profiles/verification/domain/entities/solicitud_aliado.dart';
import 'package:mani/features/profiles/verification/domain/failures/verificacion_failure.dart';
import 'package:mani/features/profiles/verification/presentation/bloc/bandeja_verificacion_cubit.dart';

import '../fakes.dart';

void main() {
  late FakeVerificacionRepository repo;
  late FakeUrlOpener opener;
  late BandejaVerificacionCubit cubit;

  setUp(() {
    repo = FakeVerificacionRepository([
      aliado(id: 'a1', nombre: 'Ana Ruiz', diasEspera: 5),
      aliado(
        id: 'a2',
        nombre: 'Beto Díaz',
        diasEspera: 3,
        categorias: ['Electricidad'],
      ),
      aliado(id: 'a3', nombre: 'Caro Gil', diasEspera: 1),
      aliado(
        id: 'r1',
        nombre: 'Rechazado',
        estado: EstadoVerificacion.rechazado,
      ),
    ]);
    opener = FakeUrlOpener();
    cubit = crearCubit(repo, opener: opener);
  });

  tearDown(() => cubit.close());

  group('cargar', () {
    test('pasa por cargando y queda listo con la lista ordenada', () async {
      final estados = <EstadoCarga>[];
      final sub = cubit.stream.listen((s) => estados.add(s.carga));

      await cubit.cargar();
      await sub.cancel();

      expect(estados.first, EstadoCarga.cargando);
      expect(cubit.state.carga, EstadoCarga.listo);
      expect(cubit.state.visibles.map((a) => a.id), ['a1', 'a2', 'a3']);
      expect(cubit.state.conteo(EstadoVerificacion.pendiente), 3);
      expect(cubit.state.conteo(EstadoVerificacion.rechazado), 1);
    });

    test('un error inicial deja la pantalla en estado error', () async {
      repo.fallarAlListar = const VerificacionFailure(
        VerificacionErrorTipo.noAutorizado,
      );

      await cubit.cargar();

      expect(cubit.state.carga, EstadoCarga.error);
      expect(cubit.state.error?.tipo, VerificacionErrorTipo.noAutorizado);
    });

    test(
      'un error al refrescar conserva la lista y muestra un aviso',
      () async {
        await cubit.cargar();
        repo.fallarAlListar = const VerificacionFailure(
          VerificacionErrorTipo.sinConexion,
        );

        await cubit.cargar(silencioso: true);

        expect(cubit.state.carga, EstadoCarga.listo);
        expect(cubit.state.solicitudes, hasLength(4));
        expect(cubit.state.aviso?.esError, isTrue);
      },
    );

    test(
      'al refrescar descarta la selección si el aliado ya no existe',
      () async {
        await cubit.cargar();
        await cubit.seleccionar('a2');
        repo.eliminar('a2');

        await cubit.cargar(silencioso: true);

        expect(cubit.state.seleccionadaId, isNull);
      },
    );
  });

  group('filtros', () {
    setUp(() => cubit.cargar());

    test(
      'cambiarFiltro muestra solo ese estado y limpia la selección',
      () async {
        await cubit.seleccionar('a1');
        cubit.cambiarFiltro(EstadoVerificacion.rechazado);

        expect(cubit.state.visibles.map((a) => a.id), ['r1']);
        expect(cubit.state.seleccionadaId, isNull);
      },
    );

    test('buscar filtra dentro de la pestaña actual', () {
      cubit.buscar('electri');
      expect(cubit.state.visibles.map((a) => a.id), ['a2']);
    });
  });

  group('seleccionar', () {
    setUp(() => cubit.cargar());

    test('trae el detalle fresco del servidor', () async {
      repo.resueltoPorOtroAdmin('a1', EstadoVerificacion.aprobado);

      await cubit.seleccionar('a1');

      expect(cubit.state.seleccionadaId, 'a1');
      expect(cubit.state.seleccionada?.estado, EstadoVerificacion.aprobado);
      expect(cubit.state.cargandoDetalleId, isNull);
    });

    test('si el aliado ya no existe lo quita de la bandeja y avisa', () async {
      repo.eliminar('a1');

      await cubit.seleccionar('a1');

      expect(cubit.state.porId('a1'), isNull);
      expect(cubit.state.seleccionadaId, isNull);
      expect(cubit.state.aviso?.mensaje, contains('ya no existe'));
    });
  });

  group('aprobar', () {
    setUp(() => cubit.cargar());

    test('aprueba, avisa y avanza al siguiente pendiente', () async {
      await cubit.seleccionar('a1');

      final ok = await cubit.aprobar('a1');

      expect(ok, isTrue);
      expect(cubit.state.porId('a1')?.estado, EstadoVerificacion.aprobado);
      expect(cubit.state.seleccionadaId, 'a2');
      expect(cubit.state.visibles.map((a) => a.id), ['a2', 'a3']);
      expect(cubit.state.aviso?.mensaje, contains('Ana Ruiz fue aprobado'));
      expect(cubit.state.procesandoId, isNull);
    });

    test('al aprobar el último pendiente retrocede al anterior', () async {
      await cubit.seleccionar('a3');
      await cubit.aprobar('a3');
      expect(cubit.state.seleccionadaId, 'a2');
    });

    test(
      'marca procesando y bloquea una segunda decisión simultánea',
      () async {
        repo.pausaResolver = Completer<void>();

        final primera = cubit.aprobar('a1');
        expect(cubit.state.procesandoId, 'a1');
        final segunda = await cubit.aprobar('a2');

        expect(segunda, isFalse);
        repo.pausaResolver!.complete();
        expect(await primera, isTrue);
        expect(repo.llamadasResolver, 1);
      },
    );

    test(
      'si otro admin se adelantó (409) avisa y refresca el aliado',
      () async {
        repo.resueltoPorOtroAdmin('a1', EstadoVerificacion.rechazado);

        final ok = await cubit.aprobar('a1');

        expect(ok, isFalse);
        expect(cubit.state.porId('a1')?.estado, EstadoVerificacion.rechazado);
        expect(cubit.state.procesandoId, isNull);
      },
    );

    test('un error conserva el estado y lo informa', () async {
      repo.fallarAlResolver = const VerificacionFailure(
        VerificacionErrorTipo.sinConexion,
      );

      final ok = await cubit.aprobar('a1');

      expect(ok, isFalse);
      expect(cubit.state.porId('a1')?.estaPendiente, isTrue);
      expect(cubit.state.aviso?.mensaje, contains('Sin conexión'));
    });
  });

  group('rechazar', () {
    setUp(() => cubit.cargar());

    test('rechaza con motivo y avisa', () async {
      final ok = await cubit.rechazar('a2', 'Documento vencido.');

      expect(ok, isTrue);
      expect(cubit.state.porId('a2')?.estado, EstadoVerificacion.rechazado);
      expect(cubit.state.porId('a2')?.motivoRechazo, 'Documento vencido.');
      expect(cubit.state.conteo(EstadoVerificacion.rechazado), 2);
    });

    test('con motivo inválido no llama al servidor', () async {
      final ok = await cubit.rechazar('a2', 'corto');

      expect(ok, isFalse);
      expect(repo.llamadasResolver, 0);
      expect(cubit.state.aviso?.esError, isTrue);
    });
  });

  group('abrirDocumento', () {
    test('abre la URL firmada', () async {
      await cubit.abrirDocumento(doc('d1', ruta: 'kyc/t/c.pdf'));
      expect(
        opener.abiertas.single.toString(),
        'https://storage.test/kyc/t/c.pdf',
      );
    });

    test('si el archivo no está disponible avisa sin romper', () async {
      repo.fallarUrl = const VerificacionFailure(
        VerificacionErrorTipo.documentoNoDisponible,
      );
      await cubit.abrirDocumento(doc('d1'));
      expect(
        cubit.state.aviso?.mensaje,
        contains('No pudimos abrir el documento'),
      );
    });

    test('si el sistema no puede abrir la URL avisa', () async {
      opener.resultado = false;
      await cubit.abrirDocumento(doc('d1'));
      expect(cubit.state.aviso?.esError, isTrue);
    });
  });

  test(
    'dos avisos iguales seguidos tienen ids distintos (ambos se muestran)',
    () async {
      repo.fallarUrl = const VerificacionFailure(
        VerificacionErrorTipo.documentoNoDisponible,
      );
      await cubit.abrirDocumento(doc('d1'));
      final primero = cubit.state.aviso;
      await cubit.abrirDocumento(doc('d1'));
      expect(cubit.state.aviso, isNot(primero));
    },
  );
}
