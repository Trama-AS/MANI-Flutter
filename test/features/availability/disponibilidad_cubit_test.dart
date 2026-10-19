import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/availability/domain/entities/ausencia.dart';
import 'package:mani/features/availability/domain/failures/disponibilidad_failure.dart';
import 'package:mani/features/availability/presentation/bloc/disponibilidad_cubit.dart';

import 'fakes.dart';

void main() {
  group('BorradorAusencia.validar', () {
    BorradorAusencia borrador(DateTime inicio, DateTime fin, {String? nota}) =>
        BorradorAusencia(
          inicio: inicio,
          fin: fin,
          motivo: MotivoAusencia.otro,
          nota: nota,
        );

    test('acepta un intervalo futuro bien formado', () {
      expect(
        borrador(
          DateTime(2026, 10, 20),
          DateTime(2026, 10, 21),
        ).validar(ahoraFijo),
        isNull,
      );
    });

    test('rechaza fin no posterior al inicio, ausencias pasadas y largas', () {
      final ini = DateTime(2026, 10, 20, 8);
      expect(borrador(ini, ini).validar(ahoraFijo), contains('posterior'));
      expect(
        borrador(
          DateTime(2026, 10, 1),
          DateTime(2026, 10, 2),
        ).validar(ahoraFijo),
        contains('futuro'),
      );
      expect(
        borrador(ini, ini.add(const Duration(days: 366))).validar(ahoraFijo),
        contains('365'),
      );
      expect(
        borrador(
          ini,
          ini.add(const Duration(hours: 1)),
          nota: 'x' * 281,
        ).validar(ahoraFijo),
        contains('280'),
      );
    });
  });

  test('cargar trae las ausencias y el estado actual', () async {
    final cubit = cubitCon(
      FakeDisponibilidadRepository(ausencias: [vacaciones]),
    );

    await cubit.cargar();

    expect(cubit.state.carga, CargaDisponibilidad.listo);
    expect(cubit.state.ausencias, [vacaciones]);
    expect(cubit.state.disponibleAhora, isTrue);
  });

  test('un error de carga queda en falla y se puede reintentar', () async {
    final repo = FakeDisponibilidadRepository(
      fallaCarga: const DisponibilidadFailure(
        DisponibilidadErrorTipo.sinConexion,
      ),
    );
    final cubit = cubitCon(repo);

    await cubit.cargar();
    expect(cubit.state.carga, CargaDisponibilidad.error);
    expect(cubit.state.falla?.tipo, DisponibilidadErrorTipo.sinConexion);

    repo.fallaCarga = null;
    await cubit.cargar();
    expect(cubit.state.carga, CargaDisponibilidad.listo);
  });

  test(
    'crear una ausencia que cubre ahora deja al aliado no disponible',
    () async {
      final cubit = cubitCon(FakeDisponibilidadRepository());
      await cubit.cargar();

      final ok = await cubit.crear(
        BorradorAusencia(
          inicio: DateTime(2026, 10, 17, 7),
          fin: DateTime(2026, 10, 18, 7),
          motivo: MotivoAusencia.enfermedad,
        ),
      );

      expect(ok, isTrue);
      expect(cubit.state.disponibleAhora, isFalse);
      expect(cubit.state.ausencias.single.activa, isTrue);
      expect(cubit.state.aviso?.esError, isFalse);
    },
  );

  test('un solapamiento devuelve false y avisa el error de negocio', () async {
    final cubit = cubitCon(
      FakeDisponibilidadRepository(ausencias: [vacaciones]),
    );
    await cubit.cargar();

    final ok = await cubit.crear(
      BorradorAusencia(
        inicio: DateTime(2026, 10, 24),
        fin: DateTime(2026, 10, 27),
        motivo: MotivoAusencia.otro,
      ),
    );

    expect(ok, isFalse);
    expect(cubit.state.aviso?.esError, isTrue);
    expect(cubit.state.aviso?.mensaje, contains('se cruza'));
    expect(cubit.state.ausencias, [vacaciones]);
  });

  test('editar y eliminar actualizan la lista desde el servidor', () async {
    final repo = FakeDisponibilidadRepository(ausencias: [vacaciones]);
    final cubit = cubitCon(repo);
    await cubit.cargar();

    await cubit.editar(
      'aus-1',
      BorradorAusencia(
        inicio: vacaciones.inicio,
        fin: DateTime(2026, 10, 26, 18),
        motivo: MotivoAusencia.vacaciones,
      ),
    );
    expect(cubit.state.ausencias.single.fin, DateTime(2026, 10, 26, 18));

    await cubit.eliminar('aus-1');
    expect(cubit.state.ausencias, isEmpty);
    expect(cubit.state.disponibleAhora, isTrue);
  });

  test('si la ausencia ya no existe, avisa y recarga la lista', () async {
    final repo = FakeDisponibilidadRepository(ausencias: [vacaciones]);
    final cubit = cubitCon(repo);
    await cubit.cargar();
    repo.ausencias.clear();
    final cargasAntes = repo.llamadasCarga;

    await cubit.eliminar('aus-1');

    expect(cubit.state.aviso?.esError, isTrue);
    expect(repo.llamadasCarga, cargasAntes + 1);
    expect(cubit.state.ausencias, isEmpty);
  });
}
