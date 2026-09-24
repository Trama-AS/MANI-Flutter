import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/profiles/verification/domain/entities/decision_verificacion.dart';
import 'package:mani/features/profiles/verification/domain/entities/solicitud_aliado.dart';
import 'package:mani/features/profiles/verification/domain/failures/verificacion_failure.dart';
import 'package:mani/features/profiles/verification/domain/usecases/verificacion_usecases.dart';

import '../fakes.dart';

Matcher _falla(VerificacionErrorTipo tipo) =>
    throwsA(isA<VerificacionFailure>().having((f) => f.tipo, 'tipo', tipo));

void main() {
  group('ListarSolicitudesAliados', () {
    test(
      'ordena pendientes primero, del más antiguo al más reciente (FIFO)',
      () async {
        final repo = FakeVerificacionRepository([
          aliado(id: 'reciente', diasEspera: 1),
          aliado(
            id: 'aprobado',
            estado: EstadoVerificacion.aprobado,
            diasEspera: 9,
          ),
          aliado(id: 'antiguo', diasEspera: 6),
        ]);

        final r = await ListarSolicitudesAliados(repo)();

        expect(r.map((a) => a.id), ['antiguo', 'reciente', 'aprobado']);
      },
    );

    test(
      'las resueltas van de la decisión más reciente a la más antigua',
      () async {
        final ahora = DateTime.now();
        final repo = FakeVerificacionRepository([
          aliado(
            id: 'vieja',
            estado: EstadoVerificacion.rechazado,
            fechaVerificacion: ahora.subtract(const Duration(days: 5)),
          ),
          aliado(
            id: 'nueva',
            estado: EstadoVerificacion.aprobado,
            fechaVerificacion: ahora,
          ),
        ]);

        final r = await ListarSolicitudesAliados(repo)();

        expect(r.map((a) => a.id), ['nueva', 'vieja']);
      },
    );
  });

  group('AprobarAliado', () {
    test('delega en el repositorio con una Aprobacion', () async {
      final repo = FakeVerificacionRepository([aliado()]);

      final r = await AprobarAliado(repo)(repo.porId('a1')!);

      expect(repo.ultimaDecision, const DecisionVerificacion.aprobar());
      expect(r.estado, EstadoVerificacion.aprobado);
    });

    test('no aprueba sin documentos y no llama a la red', () {
      final repo = FakeVerificacionRepository([aliado(documentos: const [])]);

      expect(
        () => AprobarAliado(repo)(repo.porId('a1')!),
        _falla(VerificacionErrorTipo.sinDocumentos),
      );
      expect(repo.llamadasResolver, 0);
    });

    test('no aprueba una solicitud ya resuelta', () {
      final repo = FakeVerificacionRepository([
        aliado(estado: EstadoVerificacion.rechazado),
      ]);

      expect(
        () => AprobarAliado(repo)(repo.porId('a1')!),
        _falla(VerificacionErrorTipo.yaResuelta),
      );
      expect(repo.llamadasResolver, 0);
    });
  });

  group('RechazarAliado', () {
    test('envía el motivo recortado', () async {
      final repo = FakeVerificacionRepository([aliado()]);

      final r = await RechazarAliado(repo)(
        repo.porId('a1')!,
        '  La cédula está vencida  ',
      );

      expect(
        (repo.ultimaDecision! as Rechazo).motivo,
        'La cédula está vencida',
      );
      expect(r.motivoRechazo, 'La cédula está vencida');
      expect(r.estado, EstadoVerificacion.rechazado);
    });

    test('valida el motivo antes de llamar a la red', () {
      final repo = FakeVerificacionRepository([aliado()]);

      expect(
        () => RechazarAliado(repo)(repo.porId('a1')!, 'corto'),
        _falla(VerificacionErrorTipo.motivoInvalido),
      );
      expect(repo.llamadasResolver, 0);
    });

    test(
      'permite rechazar a un aliado sin documentos (para pedirle que los cargue)',
      () async {
        final repo = FakeVerificacionRepository([aliado(documentos: const [])]);

        final r = await RechazarAliado(repo)(
          repo.porId('a1')!,
          'Falta un documento obligatorio',
        );

        expect(r.estado, EstadoVerificacion.rechazado);
      },
    );

    test('no rechaza una solicitud ya resuelta', () {
      final repo = FakeVerificacionRepository([
        aliado(estado: EstadoVerificacion.aprobado),
      ]);

      expect(
        () => RechazarAliado(repo)(repo.porId('a1')!, 'Documento ilegible'),
        _falla(VerificacionErrorTipo.yaResuelta),
      );
    });
  });

  test('ObtenerUrlDocumento delega en el repositorio', () async {
    final repo = FakeVerificacionRepository([]);
    final url = await ObtenerUrlDocumento(repo)(doc('d1', ruta: 'kyc/t/x.pdf'));
    expect(url.toString(), 'https://storage.test/kyc/t/x.pdf');
  });
}
