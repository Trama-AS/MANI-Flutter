import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/features/services/categories/data/models/categoria_servicio_model.dart';
import 'package:mani/features/services/categories/data/repositories/categorias_repository_impl.dart';
import 'package:mani/features/services/categories/domain/entities/flujo_operativo.dart';
import 'package:mani/features/services/categories/domain/entities/nueva_categoria.dart';
import 'package:mani/features/services/categories/domain/failures/categoria_failure.dart';

import '../fakes.dart';

Matcher _falla(CategoriaErrorTipo tipo) =>
    throwsA(isA<CategoriaFailure>().having((f) => f.tipo, 'tipo', tipo));

NuevaCategoria _nueva(
  String nombre, {
  FlujoOperativo flujo = FlujoOperativo.cotizacionPrevia,
  bool activa = true,
}) => NuevaCategoria.crear(nombre: nombre, flujo: flujo, activa: activa);

void main() {
  group('CategoriaServicioModel.fromJson', () {
    test('mapea el JSON de _cat_json', () {
      final m = CategoriaServicioModel.fromJson({
        'id': 'c1',
        'nombre': 'Cerrajería',
        'estado': 'INACTIVO',
        'flujo_operativo': 'TARIFA_ESTANDAR',
        'created_at': '2026-09-22T15:00:00Z',
        'aliados': 4,
      });

      expect(m.nombre, 'Cerrajería');
      expect(m.activa, isFalse);
      expect(m.flujo, FlujoOperativo.tarifaEstandar);
      expect(m.fechaCreacion?.toUtc(), DateTime.utc(2026, 9, 22, 15));
      expect(m.aliadosAsociados, 4);
    });

    test('tolera flujo desconocido y campos ausentes', () {
      final m = CategoriaServicioModel.fromJson({
        'id': 'c1',
        'nombre': 'Vieja',
        'estado': 'ACTIVO',
        'flujo_operativo': 'LEGACY',
      });
      expect(m.flujo, isNull);
      expect(m.activa, isTrue);
      expect(m.aliadosAsociados, 0);
      expect(m.fechaCreacion, isNull);
    });
  });

  test('mapearMensaje traduce cada código MANI-CAT-*', () {
    const casos = {
      'MANI-CAT-401: x': CategoriaErrorTipo.sinSesion,
      'MANI-CAT-403: x': CategoriaErrorTipo.noAutorizado,
      'MANI-CAT-409: x': CategoriaErrorTipo.nombreDuplicado,
      'MANI-CAT-422N: x': CategoriaErrorTipo.nombreInvalido,
      'MANI-CAT-422F: x': CategoriaErrorTipo.flujoInvalido,
      'JWT expired': CategoriaErrorTipo.sinSesion,
      'algo raro': CategoriaErrorTipo.desconocido,
    };
    casos.forEach((mensaje, tipo) {
      expect(
        CategoriasRepositoryImpl.mapearMensaje(mensaje).tipo,
        tipo,
        reason: mensaje,
      );
    });
  });

  group('CategoriasRepositoryImpl', () {
    late ServidorCategoriasFake servidor;
    late List<Map<String, dynamic>> logs;
    late CategoriasRepositoryImpl repo;

    setUp(() {
      servidor = ServidorCategoriasFake()
        ..sembrar(tenantId: 'tenant-a', nombre: 'Plomería', aliados: 3)
        ..sembrar(tenantId: 'tenant-b', nombre: 'Jardinería');
      logs = [];
      repo = CategoriasRepositoryImpl(
        servidor,
        logger: StructuredLogger(
          canal: 'test',
          sink: (l) => logs.add(jsonDecode(l) as Map<String, dynamic>),
        ),
      );
    });

    test(
      'listar devuelve solo las categorías del tenant de la sesión',
      () async {
        final r = await repo.listar();
        expect(r.map((c) => c.nombre), ['Plomería']);
        expect(r.single.aliadosAsociados, 3);
      },
    );

    test('crear envía el código del flujo y la visibilidad', () async {
      final c = await repo.crear(
        _nueva(
          'Cerrajería',
          flujo: FlujoOperativo.tarifaEstandar,
          activa: false,
        ),
      );
      expect(c.flujo, FlujoOperativo.tarifaEstandar);
      expect(c.activa, isFalse);
      expect(servidor.delTenant('tenant-a').last['estado'], 'INACTIVO');
    });

    test('registra un log estructurado con los campos obligatorios', () async {
      await repo.crear(_nueva('Cerrajería'));

      final log = logs.single;
      for (final campo in [
        'timestamp',
        'level',
        'service_id',
        'trace_id',
        'tenant_id',
        'message',
      ]) {
        expect(log.containsKey(campo), isTrue, reason: campo);
      }
      expect(log['level'], 'INFO');
      expect(log['message'], 'categoria_creada');
      expect(log['event'], 'US-03.1.1.crear_categoria');
      expect(log['tenant_id'], 'tenant-a');
      expect(log['flujo_operativo'], 'COTIZACION_PREVIA');
    });

    test(
      'un nombre repetido en el tenant responde nombreDuplicado y log ERROR',
      () async {
        await expectLater(
          repo.crear(_nueva('  PLOMERÍA ')),
          _falla(CategoriaErrorTipo.nombreDuplicado),
        );
        expect(logs.single['level'], 'ERROR');
        expect(logs.single['error'], 'nombreDuplicado');
      },
    );

    test('el mismo nombre en OTRO tenant sí se permite', () async {
      final c = await repo.crear(_nueva('Jardinería'));
      expect(c.nombre, 'Jardinería');
    });

    test('sin rol de admin lanza noAutorizado', () async {
      servidor.rolSesion = 'ALIADO';
      await expectLater(repo.listar(), _falla(CategoriaErrorTipo.noAutorizado));
    });

    test('sin sesión lanza sinSesion', () async {
      servidor.haySesion = false;
      await expectLater(
        repo.crear(_nueva('Pintura')),
        _falla(CategoriaErrorTipo.sinSesion),
      );
    });

    test('errores de red se traducen a sinConexion', () async {
      servidor.errorDeRed = TimeoutException('lento');
      await expectLater(repo.listar(), _falla(CategoriaErrorTipo.sinConexion));
    });
  });
}
