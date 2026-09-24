import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/asignacion/domain/entities/motivo_rechazo.dart';
import 'package:mani/features/asignacion/domain/entities/solicitud_entity.dart';
import 'package:mani/features/asignacion/domain/failures/asignacion_failure.dart';
import 'package:mani/features/asignacion/presentation/bloc/solicitudes_aliado_cubit.dart';

import '../fakes.dart';

void main() {
  late FakeAsignacionRepository repo;
  late SolicitudesAliadoCubit cubit;

  setUp(() {
    repo = FakeAsignacionRepository([
      solicitud('s1', categoria: 'Plomería', minutosAtras: 40),
      solicitud('s2', categoria: 'Electricidad', minutosAtras: 5),
      solicitud(
        'm1',
        estado: EstadoSolicitud.asignada,
        esMia: true,
        direccion: 'Calle 1',
      ),
    ]);
    cubit = crearCubit(repo);
  });

  tearDown(() => cubit.close());

  group('cargar', () {
    test('reparte la bandeja y abre en Disponibles', () async {
      await cubit.cargar();

      expect(cubit.state.carga, CargaSolicitudes.listo);
      expect(cubit.state.pestana, PestanaSolicitudes.disponibles);
      expect(cubit.state.visibles.map((s) => s.id), ['s1', 's2']);
      expect(cubit.state.bandeja.misTrabajos.single.id, 'm1');
    });

    test('un aliado sin verificar queda en estado error explicativo', () async {
      repo.fallarAlListar = const AsignacionFailure(
        AsignacionErrorTipo.aliadoNoVerificado,
      );

      await cubit.cargar();

      expect(cubit.state.carga, CargaSolicitudes.error);
      expect(cubit.state.error?.tipo, AsignacionErrorTipo.aliadoNoVerificado);
    });

    test('un error al refrescar conserva la bandeja y avisa', () async {
      await cubit.cargar();
      repo.fallarAlListar = const AsignacionFailure(
        AsignacionErrorTipo.sinConexion,
      );

      await cubit.cargar(silencioso: true);

      expect(cubit.state.carga, CargaSolicitudes.listo);
      expect(cubit.state.bandeja.disponibles, hasLength(2));
      expect(cubit.state.aviso?.tipo, TipoAviso.error);
    });
  });

  test('cambiarPestana muestra mis trabajos', () async {
    await cubit.cargar();
    cubit.cambiarPestana(PestanaSolicitudes.misTrabajos);
    expect(cubit.state.visibles.map((s) => s.id), ['m1']);
  });

  group('aceptar', () {
    setUp(() => cubit.cargar());

    test('al ganar la mueve a Mis trabajos, la resalta y celebra', () async {
      final gano = await cubit.aceptar('s1');

      expect(gano, isTrue);
      expect(cubit.state.pestana, PestanaSolicitudes.misTrabajos);
      expect(cubit.state.visibles.first.id, 's1');
      expect(cubit.state.visibles.first.direccion, isNotNull);
      expect(cubit.state.recienAsignadaId, 's1');
      expect(cubit.state.bandeja.disponibles.map((s) => s.id), ['s2']);
      expect(cubit.state.aviso?.tipo, TipoAviso.exito);
      expect(cubit.state.aviso?.mensaje, contains('es tuya'));
      expect(cubit.state.procesando, isFalse);
    });

    test('si otro aliado ganó (409) la quita, explica y refresca', () async {
      repo.tomadaPorOtroAliado('s1');

      final gano = await cubit.aceptar('s1');

      expect(gano, isFalse);
      expect(cubit.state.bandeja.porId('s1'), isNull);
      expect(cubit.state.aviso?.mensaje, contains('Otro aliado'));
      expect(cubit.state.pestana, PestanaSolicitudes.disponibles);
      expect(cubit.state.procesando, isFalse);
    });

    test('marca "aceptando" y bloquea otra acción simultánea', () async {
      repo.pausa = Completer<void>();

      final primera = cubit.aceptar('s1');
      expect(cubit.state.procesandoId, 's1');
      expect(cubit.state.accion, AccionSolicitud.aceptando);
      expect(await cubit.aceptar('s2'), isFalse);
      expect(await cubit.rechazar('s2'), isFalse);

      repo.pausa!.complete();
      expect(await primera, isTrue);
      expect(repo.llamadasAceptar, 1);
      expect(repo.llamadasRechazar, 0);
    });

    test('un error de red conserva la solicitud para reintentar', () async {
      repo.fallarAlAceptar = const AsignacionFailure(
        AsignacionErrorTipo.sinConexion,
      );

      expect(await cubit.aceptar('s1'), isFalse);
      expect(cubit.state.bandeja.porId('s1'), isNotNull);
      expect(cubit.state.aviso?.mensaje, contains('Sin conexión'));
    });
  });

  group('rechazar', () {
    setUp(() => cubit.cargar());

    test('la quita de mi bandeja con el motivo elegido', () async {
      final ok = await cubit.rechazar(
        's2',
        motivo: MotivoRechazo.noEsMiEspecialidad,
      );

      expect(ok, isTrue);
      expect(repo.rechazadas['s2'], MotivoRechazo.noEsMiEspecialidad);
      expect(cubit.state.bandeja.disponibles.map((s) => s.id), ['s1']);
      expect(cubit.state.aviso?.tipo, TipoAviso.info);
      expect(cubit.state.aviso?.mensaje, contains('otros aliados'));
    });

    test('marca "rechazando" mientras se envía', () async {
      repo.pausa = Completer<void>();
      final r = cubit.rechazar('s2');
      expect(cubit.state.accion, AccionSolicitud.rechazando);
      repo.pausa!.complete();
      await r;
      expect(cubit.state.procesando, isFalse);
    });
  });
}
