import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/profiles/coverage/data/datasources/cobertura_remote_datasource.dart';
import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/features/profiles/coverage/data/models/zona_model.dart';
import 'package:mani/features/profiles/coverage/data/repositories/cobertura_repository_impl.dart';
import 'package:mani/features/profiles/coverage/domain/entities/seleccion_cobertura.dart';
import 'package:mani/features/profiles/coverage/domain/entities/zona.dart';
import 'package:mani/features/profiles/coverage/domain/failures/cobertura_failure.dart';
import 'package:mani/features/profiles/coverage/domain/usecases/cobertura_usecases.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fakes.dart';

class _FakeDs implements CoberturaRemoteDataSource {
  Object? error;
  List<String>? enviado;

  @override
  String? get tenantIdSesion => 't1';

  @override
  Future<List<Map<String, dynamic>>> declararCobertura(
    List<String> zonaIds,
  ) async {
    enviado = zonaIds;
    if (error != null) throw error!;
    return [
      for (final id in zonaIds)
        {'zona_id': id, 'fecha_declaracion': '2026-09-22T00:00:00Z'},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> listarZonas(String? padreId) async => [
    {
      'id': 'cha',
      'nombre': 'Chapinero',
      'nivel': 'localidad',
      'zona_padre_id': 'bog',
      'ancestros': ['bog'],
      'tiene_hijas': true,
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> buscarZonas(
    String ciudadId,
    String texto,
  ) async => const [];

  @override
  Future<List<Map<String, dynamic>>> obtenerMiCobertura() async => const [];
}

void main() {
  group('DeclararCobertura (use case)', () {
    test('selección vacía falla sin llamar al repositorio', () async {
      final repo = FakeCoberturaRepository();
      expect(
        () => DeclararCobertura(repo)(SeleccionCobertura.vacia()),
        throwsA(
          isA<CoberturaFailure>().having(
            (f) => f.tipo,
            'tipo',
            CoberturaErrorTipo.seleccionVacia,
          ),
        ),
      );
      expect(repo.llamadasDeclarar, 0);
    });

    test('más de 200 zonas falla con limiteExcedido', () {
      final muchas = List.generate(
        201,
        (i) => Zona(
          id: 'z$i',
          nombre: 'Z$i',
          nivel: NivelZona.barrio,
          ancestros: const ['x'],
        ),
      );
      expect(
        () => DeclararCobertura(FakeCoberturaRepository())(
          SeleccionCobertura.desde(muchas),
        ),
        throwsA(
          isA<CoberturaFailure>().having(
            (f) => f.tipo,
            'tipo',
            CoberturaErrorTipo.limiteExcedido,
          ),
        ),
      );
    });

    test('con zonas desactivadas no envía', () {
      expect(
        () => DeclararCobertura(FakeCoberturaRepository())(
          SeleccionCobertura.desde([nizaDesactivada]),
        ),
        throwsA(
          isA<CoberturaFailure>().having(
            (f) => f.tipo,
            'tipo',
            CoberturaErrorTipo.zonaInvalida,
          ),
        ),
      );
    });

    test('envía solo ids normalizados', () async {
      final repo = FakeCoberturaRepository();
      await DeclararCobertura(repo)(
        SeleccionCobertura.desde([chico, chapinero, niza]),
      );
      expect(repo.ultimoEnvio, {'cha', 'niz'});
    });
  });

  group('CoberturaRepositoryImpl', () {
    test('mapea códigos MANI-COB-* de la RPC', () {
      final casos = {
        'MANI-COB-401: sesión sin tenant': CoberturaErrorTipo.sinSesion,
        'MANI-COB-403: el usuario no tiene perfil de aliado':
            CoberturaErrorTipo.noEsAliado,
        'MANI-COB-403R: aliado rechazado': CoberturaErrorTipo.aliadoRechazado,
        'MANI-COB-422V: debe seleccionar al menos una zona':
            CoberturaErrorTipo.seleccionVacia,
        'MANI-COB-422L: máximo 200': CoberturaErrorTipo.limiteExcedido,
        'MANI-COB-422Z: zonas desactivadas': CoberturaErrorTipo.zonaInvalida,
        'algo raro': CoberturaErrorTipo.desconocido,
      };
      casos.forEach(
        (msg, tipo) => expect(
          CoberturaRepositoryImpl.mapearMensaje(msg).tipo,
          tipo,
          reason: msg,
        ),
      );
    });

    test(
      'PostgrestException se convierte en CoberturaFailure y se registra log ERROR',
      () async {
        final logs = <String>[];
        final ds = _FakeDs()
          ..error = PostgrestException(
            message: 'MANI-COB-422Z: una o más zonas no existen',
          );
        final repo = CoberturaRepositoryImpl(
          ds,
          logger: StructuredLogger(canal: 'mani.cobertura', sink: logs.add),
        );
        await expectLater(
          repo.declararCobertura({'x'}),
          throwsA(
            isA<CoberturaFailure>().having(
              (f) => f.tipo,
              'tipo',
              CoberturaErrorTipo.zonaInvalida,
            ),
          ),
        );
        expect(logs.single, contains('"level":"ERROR"'));
        expect(logs.single, contains('"tenant_id":"t1"'));
      },
    );

    test(
      'éxito devuelve ids guardados y log INFO con campos obligatorios',
      () async {
        final logs = <String>[];
        final repo = CoberturaRepositoryImpl(
          _FakeDs(),
          logger: StructuredLogger(canal: 'mani.cobertura', sink: logs.add),
        );
        final r = await repo.declararCobertura({'cha', 'niz'});
        expect(r, {'cha', 'niz'});
        for (final campo in [
          'timestamp',
          'level',
          'service_id',
          'trace_id',
          'tenant_id',
          'message',
        ]) {
          expect(logs.single, contains('"$campo"'));
        }
      },
    );

    test('ZonaModel.fromJson tolera nivel desconocido y estado ausente', () {
      final z = ZonaModel.fromJson({
        'id': '1',
        'nombre': 'UPZ 1',
        'nivel': 'upz',
        'zona_padre_id': null,
      });
      expect(z.nivel, NivelZona.otro);
      expect(z.activa, isTrue);
      expect(z.ancestros, isEmpty);
    });
  });
}
