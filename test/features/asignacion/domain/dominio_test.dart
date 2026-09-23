import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/asignacion/data/models/solicitud_model.dart';
import 'package:mani/features/asignacion/domain/entities/bandeja_solicitudes.dart';
import 'package:mani/features/asignacion/domain/entities/modalidad_servicio.dart';
import 'package:mani/features/asignacion/domain/entities/motivo_rechazo.dart';
import 'package:mani/features/asignacion/domain/entities/regla_sitio.dart';
import 'package:mani/features/asignacion/domain/entities/solicitud_entity.dart';
import 'package:mani/features/asignacion/domain/failures/asignacion_failure.dart';
import 'package:mani/features/asignacion/domain/usecases/asignacion_usecases.dart';

import '../fakes.dart';

Matcher _falla(AsignacionErrorTipo tipo) =>
    throwsA(isA<AsignacionFailure>().having((f) => f.tipo, 'tipo', tipo));

void main() {
  group('SolicitudEntity', () {
    test('EstadoSolicitud traduce los valores de BD de los seeds', () {
      expect(EstadoSolicitud.desde('PENDIENTE'), EstadoSolicitud.pendiente);
      expect(EstadoSolicitud.desde('asignada'), EstadoSolicitud.asignada);
      expect(EstadoSolicitud.desde('EN_CURSO'), EstadoSolicitud.otro);
    });

    test('solo está disponible si sigue pendiente y no es mía', () {
      expect(solicitud('1').estaDisponible, isTrue);
      expect(
        solicitud('2', estado: EstadoSolicitud.asignada).estaDisponible,
        isFalse,
      );
      expect(
        solicitud(
          '3',
          estado: EstadoSolicitud.asignada,
          esMia: true,
        ).estaDisponible,
        isFalse,
      );
    });

    test('ubicación combina zona y zona superior', () {
      expect(solicitud('1').ubicacion, 'Roma Norte · Cuauhtémoc');
      expect(solicitud('1', zonaPadre: null).ubicacion, 'Roma Norte');
    });

    test('minutosEsperando cuenta desde la creación', () {
      expect(
        solicitud('1', minutosAtras: 45).minutosEsperando(DateTime.now()),
        45,
      );
    });
  });

  test('ModalidadServicio usa los códigos de flujo operativo (US-03.1.1)', () {
    expect(
      ModalidadServicio.desde('COTIZACION_PREVIA'),
      ModalidadServicio.cotizacionPrevia,
    );
    expect(
      ModalidadServicio.desde('tarifa_estandar'),
      ModalidadServicio.tarifaEstandar,
    );
    expect(ModalidadServicio.desde(null), ModalidadServicio.desconocida);
    expect(ModalidadServicio.desde(''), ModalidadServicio.desconocida);
  });

  test('ReglaSitio.desdeMapa conserva TODAS las reglas, ordenadas', () {
    final reglas = ReglaSitio.desdeMapa({
      'parqueadero': true,
      'mascotas': false,
      'horario_acceso': '8-17',
    });
    expect(reglas.map((r) => r.clave), [
      'horario_acceso',
      'mascotas',
      'parqueadero',
    ]);
    expect(ReglaSitio.desdeMapa(null), isEmpty);
  });

  test('los motivos de rechazo coinciden con el CHECK de la migración 005', () {
    expect(MotivoRechazo.values.map((m) => m.codigo).toSet(), {
      'FUERA_DE_ZONA',
      'SIN_DISPONIBILIDAD',
      'NO_ES_MI_ESPECIALIDAD',
      'OTRO',
    });
  });

  group('BandejaSolicitudes', () {
    final bandeja = BandejaSolicitudes.desde([
      solicitud('reciente', minutosAtras: 2),
      solicitud('antigua', minutosAtras: 90),
      solicitud(
        'mia-vieja',
        estado: EstadoSolicitud.asignada,
        esMia: true,
        fechaAsignacion: DateTime.now().subtract(const Duration(days: 1)),
      ),
      solicitud(
        'mia-nueva',
        estado: EstadoSolicitud.asignada,
        esMia: true,
        fechaAsignacion: DateTime.now(),
      ),
    ]);

    test('disponibles FIFO: el cliente que más espera va primero', () {
      expect(bandeja.disponibles.map((s) => s.id), ['antigua', 'reciente']);
    });

    test('mis trabajos del más reciente al más antiguo', () {
      expect(bandeja.misTrabajos.map((s) => s.id), ['mia-nueva', 'mia-vieja']);
    });

    test('conAsignada mueve la solicitud al inicio de mis trabajos', () {
      final ganada = solicitud(
        'antigua',
        estado: EstadoSolicitud.asignada,
        esMia: true,
      );
      final b = bandeja.conAsignada(ganada);
      expect(b.disponibles.map((s) => s.id), ['reciente']);
      expect(b.misTrabajos.first.id, 'antigua');
    });

    test('sin quita la solicitud de disponibles', () {
      expect(bandeja.sin('reciente').disponibles.map((s) => s.id), ['antigua']);
    });
  });

  group('Casos de uso', () {
    test('AceptarSolicitud no llama a la red si ya no está pendiente', () {
      final repo = FakeAsignacionRepository();
      expect(
        () => AceptarSolicitud(repo)(
          solicitud('1', estado: EstadoSolicitud.asignada),
        ),
        _falla(AsignacionErrorTipo.yaNoDisponible),
      );
      expect(
        () => AceptarSolicitud(repo)(
          solicitud('2', estado: EstadoSolicitud.asignada, esMia: true),
        ),
        _falla(AsignacionErrorTipo.yaEsTuya),
      );
      expect(repo.llamadasAceptar, 0);
    });

    test('AceptarSolicitud delega en el repositorio', () async {
      final repo = FakeAsignacionRepository([solicitud('1')]);
      final r = await AceptarSolicitud(repo)(repo.porId('1')!);
      expect(r.esMia, isTrue);
    });

    test('RechazarSolicitud envía el motivo y no rechaza lo propio', () async {
      final repo = FakeAsignacionRepository([solicitud('1')]);
      await RechazarSolicitud(repo)(
        repo.porId('1')!,
        motivo: MotivoRechazo.fueraDeZona,
      );
      expect(repo.rechazadas['1'], MotivoRechazo.fueraDeZona);

      expect(
        () => RechazarSolicitud(repo)(
          solicitud('2', estado: EstadoSolicitud.asignada, esMia: true),
        ),
        _falla(AsignacionErrorTipo.yaEsTuya),
      );
    });

    test('ListarSolicitudesAliado reparte la bandeja', () async {
      final repo = FakeAsignacionRepository([
        solicitud('1'),
        solicitud('2', estado: EstadoSolicitud.asignada, esMia: true),
      ]);
      final b = await ListarSolicitudesAliado(repo)();
      expect(b.disponibles.single.id, '1');
      expect(b.misTrabajos.single.id, '2');
    });
  });

  group('SolicitudModel.fromJson', () {
    test('mapea el JSON de _sol_json', () {
      final m = SolicitudModel.fromJson({
        'id': 's1',
        'estado': 'ASIGNADA',
        'es_mia': true,
        'categoria': 'Plomería',
        'flujo_operativo': 'TARIFA_ESTANDAR',
        'zona': 'Roma Norte',
        'zona_padre': 'Cuauhtémoc',
        'reglas_sitio': {'mascotas': false},
        'direccion': 'Calle Colima 120',
        'created_at': '2026-09-23T10:00:00Z',
        'asignada_at': '2026-09-23T10:05:00Z',
      });
      expect(m.estado, EstadoSolicitud.asignada);
      expect(m.esMia, isTrue);
      expect(m.modalidad, ModalidadServicio.tarifaEstandar);
      expect(m.reglasSitio.single, const ReglaSitio('mascotas', false));
      expect(m.direccion, 'Calle Colima 120');
      expect(m.fechaAsignacion?.toUtc(), DateTime.utc(2026, 9, 23, 10, 5));
    });

    test('tolera campos ausentes', () {
      final m = SolicitudModel.fromJson({'id': 's1', 'estado': 'PENDIENTE'});
      expect(m.reglasSitio, isEmpty);
      expect(m.direccion, isNull);
      expect(m.modalidad, ModalidadServicio.desconocida);
      expect(m.esMia, isFalse);
    });
  });

  test('cada tipo de falla tiene un mensaje para el usuario', () {
    for (final t in AsignacionErrorTipo.values) {
      expect(AsignacionFailure(t).mensajeUsuario, isNotEmpty, reason: t.name);
    }
  });
}
