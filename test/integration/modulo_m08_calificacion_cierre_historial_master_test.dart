import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/services/eligible_allies/domain/aliado_elegible.dart';
import 'package:mani/features/services/eligible_allies/presentation/aliados_elegibles_cubit.dart';
import 'package:mani/features/services/eligible_allies/presentation/aliados_elegibles_page.dart';
import 'package:mani/features/services/eligible_allies/data/elegibles_datasource.dart';
import 'package:mani/features/services/ratings/data/calificacion_cierre_datasource.dart';
import 'package:mani/features/services/ratings/domain/calificacion_cierre_modelos.dart';
import 'package:mani/features/services/ratings/presentation/calificacion_cierre_cubit.dart';
import 'package:mani/features/services/ratings/presentation/calificacion_cierre_widgets.dart';
import 'package:mani/features/services/tracking/domain/solicitud_seguimiento.dart';

class _FuenteModuloM08EnMemoria implements FuenteModuloM08 {
  _FuenteModuloM08EnMemoria({required this.rolActual});

  String rolActual; // 'CLIENT' | 'ALLY'
  CalificacionServicio? califCliente;
  CalificacionServicio? califAliado;
  bool cerrada = false;
  List<RegistroHistorialServicio> historialCliente = [];
  List<RegistroHistorialServicio> historialAliado = [];

  EstadoCierreSolicitud _construirCierre() {
    final tieneC = califCliente != null;
    final tieneA = califAliado != null;
    if (tieneC && tieneA) {
      cerrada = true;
    }
    return EstadoCierreSolicitud(
      cerrada: cerrada,
      estadoSolicitud: cerrada ? 'CERRADA' : 'COMPLETADA',
      cerradaEn: cerrada ? DateTime.utc(2026, 10, 28, 18, 0) : null,
      tieneCalificacionCliente: tieneC,
      tieneCalificacionAliado: tieneA,
      pendientes: [
        if (!tieneC) 'CALIFICACION_CLIENTE',
        if (!tieneA) 'CALIFICACION_ALIADO',
      ],
    );
  }

  @override
  Future<ResumenCalificacionesSolicitud> obtenerCalificaciones(
    String solicitudId,
  ) async {
    final cierre = _construirCierre();
    return ResumenCalificacionesSolicitud(
      solicitudId: solicitudId,
      estado: cierre.estadoSolicitud,
      cierre: cierre,
      clienteAAliado: califCliente,
      aliadoACliente: califAliado,
    );
  }

  @override
  Future<ResumenCalificacionesSolicitud> registrarCalificacion({
    required String solicitudId,
    required int puntaje,
    String? comentario,
  }) async {
    if (rolActual == 'CLIENT') {
      if (califCliente != null) {
        throw const ModuloM08Failure(ModuloM08ErrorTipo.calificacionDuplicada);
      }
      califCliente = CalificacionServicio(
        id: 'cal-cliente-1',
        solicitudId: solicitudId,
        autorId: 'usr-cliente-1',
        destinatarioId: 'usr-aliado-1',
        rolAutor: 'CLIENT',
        puntaje: puntaje,
        comentario: comentario,
        creadaEn: DateTime.utc(2026, 10, 28, 17, 0),
      );
    } else {
      if (califAliado != null) {
        throw const ModuloM08Failure(ModuloM08ErrorTipo.calificacionDuplicada);
      }
      califAliado = CalificacionServicio(
        id: 'cal-aliado-1',
        solicitudId: solicitudId,
        autorId: 'usr-aliado-1',
        destinatarioId: 'usr-cliente-1',
        rolAutor: 'ALLY',
        puntaje: puntaje,
        comentario: comentario,
        creadaEn: DateTime.utc(2026, 10, 28, 17, 30),
      );
    }
    return obtenerCalificaciones(solicitudId);
  }

  @override
  Future<EstadoCierreSolicitud> cerrarSolicitud(String solicitudId) async {
    final cierre = _construirCierre();
    if (!cierre.cierreCompleto) {
      throw const ModuloM08Failure(ModuloM08ErrorTipo.cierreIncompleto);
    }
    return cierre;
  }

  @override
  Future<List<CalificacionAgregadaAliado>> listarCalificacionesAliados({
    String? categoriaId,
    String? zonaId,
  }) async {
    return const [
      CalificacionAgregadaAliado(
        aliadoId: 'aliado-con-calificaciones',
        nombreRazonSocial: 'Ana Pérez',
        tipo: 'PERSONA_NATURAL',
        estadoVerificacion: 'VERIFICADO',
        calificacionPromedio: 4.8,
        totalCalificaciones: 12,
        etiquetaCalificacion: '4.8',
      ),
      CalificacionAgregadaAliado(
        aliadoId: 'aliado-sin-valorar',
        nombreRazonSocial: 'Aliado Nuevo',
        tipo: 'PERSONA_NATURAL',
        estadoVerificacion: 'VERIFICADO',
        calificacionPromedio: null,
        totalCalificaciones: 0,
        etiquetaCalificacion: 'Sin valorar',
      ),
    ];
  }

  @override
  Future<VistaPreviaPenalizacion> previsualizarCancelacion(
    String solicitudId,
  ) async {
    return VistaPreviaPenalizacion(
      solicitudId: solicitudId,
      estadoActual: 'ASIGNADA',
      cancelable: true,
      aplicaPenalizacion: true,
      montoPenalizacion: 20000,
      motivoPenalizacion: 'Cancelación tardía (20% sobre \$100.000)',
      modoCalculo: 'PORCENTAJE',
      politicaActiva: true,
    );
  }

  @override
  Future<List<RegistroHistorialServicio>> listarHistorialCliente() async =>
      historialCliente;

  @override
  Future<List<RegistroHistorialServicio>> listarHistorialAliado() async =>
      historialAliado;
}

class _FuenteElegiblesMock implements FuenteElegibles {
  _FuenteElegiblesMock(this.lista);
  final ListaElegibles lista;

  @override
  Future<ListaElegibles> listar(String solicitudId, {TipoAliado? tipo}) async =>
      lista;
}

void main() {
  group('Módulo C (M-08) — Prueba Maestra Frontend', () {
    testWidgets(
      'SCRUM-874, SCRUM-875 y SCRUM-1418: flujo bidireccional completo y cierre condicionado',
      (tester) async {
        final fuente = _FuenteModuloM08EnMemoria(rolActual: 'CLIENT');
        final cubit = CalificacionCierreCubit(fuente, solicitudId: 'sol-1001');
        await cubit.cargar();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BlocProvider.value(
                value: cubit,
                child: const SingleChildScrollView(
                  child: CalificacionCierreSeccion(esAliado: false),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Sin ambas calificaciones, verificar cierre definitivo informa error (SCRUM-1418 C2)
        await tester.tap(find.byKey(const Key('m08-cerrar-solicitud-btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('m08-calificacion-error')), findsOneWidget);
        expect(
          find.textContaining('no puede declararse cerrado'),
          findsOneWidget,
        );

        // 2. Puntaje inválido (0 estrellas seleccionadas) es rechazado (SCRUM-874 C3)
        await tester.tap(find.byKey(const Key('m08-enviar-calificacion-btn')));
        await tester.pumpAndSettle();
        expect(find.textContaining('entre 1 y 5 estrellas'), findsOneWidget);

        // 3. Cliente selecciona 5 estrellas y comentario y envía (SCRUM-874 C1)
        await tester.tap(find.byKey(const Key('m08-estrella-5')));
        await tester.pump();
        await tester.enterText(
          find.byKey(const Key('m08-comentario-input')),
          'Excelente trabajo de plomería.',
        );
        await tester.tap(find.byKey(const Key('m08-enviar-calificacion-btn')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('m08-mi-calificacion-registrada')),
          findsOneWidget,
        );
        // Sigue sin cerrarse porque falta la del aliado (SCRUM-1418 C2)
        expect(
          find.textContaining('Pendiente de calificación del aliado'),
          findsOneWidget,
        );

        // 4. El aliado califica al cliente (SCRUM-875 C1) -> transiciona a CERRADA (SCRUM-1418 C1)
        fuente.rolActual = 'ALLY';
        final okAliado = await cubit.calificar(
          puntaje: 4,
          comentario: 'Cliente puntual y amable.',
        );
        expect(okAliado, isTrue);
        await tester.pumpAndSettle();

        expect(cubit.state.resumen?.cierre.cierreCompleto, isTrue);
        expect(
          find.textContaining('Cerrada (ambas calificaciones registradas)'),
          findsOneWidget,
        );

        // 5. Intento de doble calificación del aliado es rechazado con 409 (SCRUM-875 C2)
        final duplicada = await cubit.calificar(puntaje: 5);
        expect(duplicada, isFalse);
        expect(cubit.state.error, contains('Ya registraste tu calificación'));
      },
    );

    testWidgets(
      'SCRUM-876: listado de aliados muestra promedio con conteo y "Sin valorar" (nunca 0.0) cuando no tiene calificaciones',
      (tester) async {
        final lista = ListaElegibles.fromJson({
          'matchedAllies': [
            {
              'allyId': 'aliado-1',
              'nombreRazonSocial': 'Ana Pérez',
              'tipo': 'PERSONA_NATURAL',
              'calificacionPromedio': 4.8,
              'totalCalificaciones': 12,
              'etiquetaCalificacion': '4.8',
            },
            {
              'allyId': 'aliado-2',
              'nombreRazonSocial': 'Carlos Sin Valoraciones',
              'tipo': 'PERSONA_NATURAL',
              'calificacionPromedio': null,
              'totalCalificaciones': 0,
              'etiquetaCalificacion': 'Sin valorar',
            },
          ],
          'totalCount': 2,
        });

        final cubit = AliadosElegiblesCubit(
          _FuenteElegiblesMock(lista),
          'sol-876',
        );
        await cubit.cargar();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BlocProvider.value(
                value: cubit,
                child: const AliadosElegiblesPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('★ 4.8 (12)'), findsOneWidget);
        expect(find.text('Sin valorar'), findsOneWidget);
        expect(find.textContaining('0.0'), findsNothing);
      },
    );

    testWidgets(
      'SCRUM-878: banner de vista previa de penalización muestra cargo con política activa y \$0 sin política',
      (tester) async {
        final conPenalizacion = VistaPreviaPenalizacion.fromJson({
          'solicitudId': 'sol-878-a',
          'estadoActual': 'ASIGNADA',
          'cancelable': true,
          'penalizacion': {
            'aplica': true,
            'monto': 20000,
            'motivo': 'Cancelación tardía (20%)',
            'modoCalculo': 'PORCENTAJE',
          },
          'politicaVigente': {'activa': true},
        });
        final sinPolitica = VistaPreviaPenalizacion.fromJson({
          'solicitudId': 'sol-878-b',
          'estadoActual': 'ASIGNADA',
          'cancelable': true,
          'penalizacion': {
            'aplica': false,
            'monto': 0,
            'motivo': null,
            'modoCalculo': null,
          },
          'politicaVigente': {'activa': false},
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  ResumenPenalizacionCancelacionBanner(
                    preview: conPenalizacion,
                  ),
                  ResumenPenalizacionCancelacionBanner(preview: sinPolitica),
                ],
              ),
            ),
          ),
        );

        expect(
          find.text('Penalización por cancelación tardía: \$20000'),
          findsOneWidget,
        );
        expect(
          find.text('Sin penalización por cancelación (\$0).'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'SCRUM-879 y SCRUM-880: historial de cliente y de aliado en orden cronológico y estado vacío claro',
      (tester) async {
        final fuente = _FuenteModuloM08EnMemoria(rolActual: 'CLIENT');
        final cubitCliente = HistorialServiciosCubit(fuente, esAliado: false);
        await cubitCliente.cargar();

        // 1. Estado vacío claro para cliente (SCRUM-879 C2)
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BlocProvider.value(
                value: cubitCliente,
                child: const HistorialServiciosPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Sin servicios registrados en tu historial.'),
          findsOneWidget,
        );

        // 2. Historial de cliente con servicios y penalización (SCRUM-879 C1)
        fuente.historialCliente = [
          RegistroHistorialServicio.desdeHistorialCliente({
            'id': 'sol-hist-1',
            'estado': 'CERRADA',
            'categoriaId': 'cat-1',
            'categoria': 'Plomería',
            'descripcion': 'Reparación de tubería principal',
            'direccion': 'Calle 100 #15-20',
            'zona': 'Chapinero',
            'aliado': {'id': 'ali-1', 'nombreRazonSocial': 'Ana Pérez'},
            'valorTotal': 120000,
            'penalizacion': {'aplicada': false, 'monto': 0},
            'calificaciones': {
              'emitidaAlAliado': {
                'id': 'c1',
                'solicitudId': 'sol-hist-1',
                'autorId': 'u1',
                'destinatarioId': 'u2',
                'rolAutor': 'CLIENT',
                'puntaje': 5,
                'creadaEn': '2026-10-28T17:00:00Z',
              },
            },
            'creadaEn': '2026-10-28T15:00:00Z',
          }),
          RegistroHistorialServicio.desdeHistorialCliente({
            'id': 'sol-hist-2',
            'estado': 'CANCELADA',
            'categoriaId': 'cat-2',
            'categoria': 'Electricidad',
            'descripcion': 'Revisión de tablero eléctrico',
            'direccion': 'Carrera 7 #45-10',
            'zona': 'Chapinero',
            'penalizacion': {'aplicada': true, 'monto': 20000},
            'calificaciones': {},
            'creadaEn': '2026-10-27T12:00:00Z',
          }),
        ];
        await cubitCliente.cargar();
        await tester.pumpAndSettle();

        expect(find.text('Plomería'), findsOneWidget);
        expect(find.text('Aliado: Ana Pérez'), findsOneWidget);
        expect(find.text('Penalización aplicada: \$20000'), findsOneWidget);

        // 3. Historial de trabajos del aliado (SCRUM-880 C1/C2)
        fuente.historialAliado = [
          RegistroHistorialServicio.desdeHistorialAliado({
            'id': 'job-1',
            'estado': 'CERRADA',
            'categoriaId': 'cat-1',
            'categoria': 'Plomería',
            'descripcion': 'Reparación de tubería principal',
            'direccion': 'Calle 100 #15-20',
            'zona': 'Chapinero',
            'cliente': {'id': 'cli-1', 'nombre': 'Juan Cliente'},
            'valorTotal': 120000,
            'calificaciones': {},
            'creadaEn': '2026-10-28T15:00:00Z',
          }),
        ];
        final cubitAliado = HistorialServiciosCubit(fuente, esAliado: true);
        await cubitAliado.cargar();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BlocProvider.value(
                value: cubitAliado,
                child: const HistorialServiciosPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Historial de trabajos'), findsOneWidget);
        expect(find.text('Cliente: Juan Cliente'), findsOneWidget);
      },
    );

    test(
      'GatewayFuenteModuloM08.mapearGateway traduce códigos MANI-CAL-*, MANI-PEN-* y MANI-HIS-*',
      () {
        final f422p = GatewayFuenteModuloM08.mapearGateway(
          const GatewayException(
            message: 'Puntaje inválido',
            statusCode: 422,
            cuerpo: {'code': 'MANI-CAL-422P'},
          ),
        );
        expect(f422p.tipo, ModuloM08ErrorTipo.puntajeInvalido);

        final f409d = GatewayFuenteModuloM08.mapearGateway(
          const GatewayException(
            message: 'Duplicada',
            statusCode: 409,
            cuerpo: {'code': 'MANI-CAL-409D'},
          ),
        );
        expect(f409d.tipo, ModuloM08ErrorTipo.calificacionDuplicada);

        final f409c = GatewayFuenteModuloM08.mapearGateway(
          const GatewayException(
            message: 'Sin ambas calificaciones',
            statusCode: 409,
            cuerpo: {'code': 'MANI-CAL-409C'},
          ),
        );
        expect(f409c.tipo, ModuloM08ErrorTipo.cierreIncompleto);

        expect(
          GatewayFuenteModuloM08.mapearGateway(
            const GatewayException(message: 'Sin red'),
          ).tipo,
          ModuloM08ErrorTipo.sinConexion,
        );
        expect(
          GatewayFuenteModuloM08.mapearGateway(
            const GatewayException(
              message: 'Comentario largo',
              statusCode: 422,
              cuerpo: {'code': 'MANI-CAL-422C'},
            ),
          ).tipo,
          ModuloM08ErrorTipo.comentarioInvalido,
        );
        expect(
          GatewayFuenteModuloM08.mapearGateway(
            const GatewayException(
              message: 'No ejecutado',
              statusCode: 409,
              cuerpo: {'code': 'MANI-CAL-409E'},
            ),
          ).tipo,
          ModuloM08ErrorTipo.servicioNoEjecutado,
        );
        expect(
          GatewayFuenteModuloM08.mapearGateway(
            const GatewayException(
              message: 'No autorizado',
              statusCode: 401,
              cuerpo: {'code': 'MANI-CAL-401'},
            ),
          ).tipo,
          ModuloM08ErrorTipo.sinSesion,
        );
        expect(
          GatewayFuenteModuloM08.mapearGateway(
            const GatewayException(
              message: 'Sin permiso',
              statusCode: 403,
              cuerpo: {'code': 'MANI-CAL-403P'},
            ),
          ).tipo,
          ModuloM08ErrorTipo.sinPermiso,
        );
        expect(
          GatewayFuenteModuloM08.mapearGateway(
            const GatewayException(
              message: 'No encontrado',
              statusCode: 404,
              cuerpo: {'code': 'MANI-CAL-404'},
            ),
          ).tipo,
          ModuloM08ErrorTipo.noEncontrado,
        );
        expect(
          GatewayFuenteModuloM08.mapearGateway(
            const GatewayException(message: 'Caído', statusCode: 503),
          ).tipo,
          ModuloM08ErrorTipo.servicioNoDisponible,
        );
        expect(
          GatewayFuenteModuloM08.mapearGateway(
            const GatewayException(message: 'Otro', statusCode: 400),
          ).tipo,
          ModuloM08ErrorTipo.desconocido,
        );
        for (final tipo in ModuloM08ErrorTipo.values) {
          expect(ModuloM08Failure(tipo).mensajeUsuario, isNotEmpty);
          expect(
            ModuloM08Failure(tipo, 'detalle').toString(),
            contains(tipo.name),
          );
        }
      },
    );

    test(
      'GatewayFuenteModuloM08 ejecuta todas las rutas HTTP contra el Gateway (/api/v1/core/...)',
      () async {
        final client = MockClient((req) async {
          final path = req.url.path;
          if (req.method == 'POST' && path.endsWith('/calificaciones')) {
            return http.Response(
              jsonEncode({
                'calificacion': {
                  'id': 'c-1',
                  'solicitudId': 'sol-1',
                  'autorId': 'u-1',
                  'destinatarioId': 'u-2',
                  'rolAutor': 'CLIENT',
                  'puntaje': 5,
                  'comentario': 'Muy bien',
                  'creadaEn': '2026-10-28T18:00:00Z',
                },
                'cierre': {
                  'cerrada': false,
                  'estadoSolicitud': 'COMPLETADA',
                  'tieneCalificacionCliente': true,
                  'tieneCalificacionAliado': false,
                  'pendientes': ['CALIFICACION_ALIADO'],
                },
              }),
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.method == 'GET' &&
              path.endsWith('/calificaciones') &&
              path.contains('/solicitudes/')) {
            return http.Response(
              jsonEncode({
                'solicitudId': 'sol-1',
                'estado': 'CERRADA',
                'cierre': {
                  'cerrada': true,
                  'estadoSolicitud': 'CERRADA',
                  'cerradaEn': '2026-10-28T19:00:00Z',
                  'tieneCalificacionCliente': true,
                  'tieneCalificacionAliado': true,
                  'pendientes': <String>[],
                },
                'calificaciones': {
                  'clienteAAliado': {
                    'id': 'c-1',
                    'solicitudId': 'sol-1',
                    'autorId': 'u-1',
                    'destinatarioId': 'u-2',
                    'rolAutor': 'CLIENT',
                    'puntaje': 5,
                    'creadaEn': '2026-10-28T18:00:00Z',
                  },
                  'aliadoACliente': {
                    'id': 'c-2',
                    'solicitudId': 'sol-1',
                    'autorId': 'u-2',
                    'destinatarioId': 'u-1',
                    'rolAutor': 'ALLY',
                    'puntaje': 4,
                    'creadaEn': '2026-10-28T18:30:00Z',
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.method == 'POST' && path.endsWith('/cerrar')) {
            return http.Response(
              jsonEncode({
                'cierre': {
                  'cerrada': true,
                  'estadoSolicitud': 'CERRADA',
                  'cerradaEn': '2026-10-28T19:00:00Z',
                  'tieneCalificacionCliente': true,
                  'tieneCalificacionAliado': true,
                  'pendientes': <String>[],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.method == 'GET' && path.endsWith('/aliados/calificaciones')) {
            return http.Response(
              jsonEncode({
                'aliados': [
                  {
                    'aliadoId': 'ali-1',
                    'nombreRazonSocial': 'Ana Pérez',
                    'tipo': 'PERSONA_NATURAL',
                    'estadoVerificacion': 'VERIFICADO',
                    'calificacionPromedio': 4.9,
                    'totalCalificaciones': 8,
                    'etiquetaCalificacion': '4.9',
                  },
                  {
                    'aliadoId': 'ali-2',
                    'nombreRazonSocial': 'Nuevo',
                    'tipo': 'PERSONA_NATURAL',
                    'estadoVerificacion': 'VERIFICADO',
                    'calificacionPromedio': null,
                    'totalCalificaciones': 0,
                    'etiquetaCalificacion': 'Sin valorar',
                  },
                ],
                'totalCount': 2,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.method == 'GET' && path.endsWith('/cancelacion-preview')) {
            return http.Response(
              jsonEncode({
                'solicitudId': 'sol-1',
                'estadoActual': 'ASIGNADA',
                'cancelable': true,
                'penalizacion': {
                  'aplica': true,
                  'monto': 15000,
                  'motivo': 'Cancelación tardía',
                  'modoCalculo': 'MONTO_FIJO',
                },
                'politicaVigente': {'activa': true},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.method == 'GET' &&
              path.endsWith('/solicitudes/me/historial')) {
            return http.Response(
              jsonEncode({
                'historial': [
                  {
                    'id': 'sol-1',
                    'estado': 'CERRADA',
                    'categoriaId': 'cat-1',
                    'categoria': 'Plomería',
                    'descripcion': 'Fuga de agua',
                    'direccion': 'Calle 10',
                    'zona': 'Chapinero',
                    'penalizacion': {'aplicada': false, 'monto': 0},
                    'calificaciones': {},
                    'creadaEn': '2026-10-28T10:00:00Z',
                  },
                ],
                'total': 1,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (req.method == 'GET' && path.endsWith('/allies/me/history')) {
            return http.Response(
              jsonEncode({
                'trabajos': [
                  {
                    'id': 'sol-1',
                    'estado': 'CERRADA',
                    'categoriaId': 'cat-1',
                    'categoria': 'Plomería',
                    'descripcion': 'Fuga de agua',
                    'direccion': 'Calle 10',
                    'zona': 'Chapinero',
                    'cliente': {'id': 'cli-1', 'nombre': 'Cliente Uno'},
                    'calificaciones': {},
                    'creadaEn': '2026-10-28T10:00:00Z',
                  },
                ],
                'total': 1,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(jsonEncode({'error': 'no'}), 404);
        });

        final gateway = GatewayClient(
          baseUrl: 'http://localhost',
          tokenProvider: () async => 'jwt-test',
          httpClient: client,
          maxRetries: 0,
        );
        final ds = GatewayFuenteModuloM08(gateway);

        final reg = await ds.registrarCalificacion(
          solicitudId: 'sol-1',
          puntaje: 5,
          comentario: 'Muy bien',
        );
        expect(reg.clienteAAliado?.puntaje, 5);
        expect(reg.cierre.etiquetaEstadoCierre, contains('aliado'));

        final obt = await ds.obtenerCalificaciones('sol-1');
        expect(obt.cierre.cierreCompleto, isTrue);

        final cer = await ds.cerrarSolicitud('sol-1');
        expect(cer.cerrada, isTrue);

        final aliados = await ds.listarCalificacionesAliados(
          categoriaId: 'cat-1',
          zonaId: 'zon-1',
        );
        expect(aliados.first.textoVisible, '★ 4.9 (8)');
        expect(aliados.last.textoVisible, 'Sin valorar');

        final prev = await ds.previsualizarCancelacion('sol-1');
        expect(prev.aplicaPenalizacion, isTrue);
        expect(prev.montoPenalizacion, 15000);

        final histC = await ds.listarHistorialCliente();
        expect(histC.single.id, 'sol-1');

        final histA = await ds.listarHistorialAliado();
        expect(histA.single.nombreContraparte, 'Cliente Uno');

        final seg = SolicitudSeguimiento.fromJson({
          'id': 'sol-seg-1',
          'estado': 'CANCELADA',
          'categoria': 'Plomería',
          'zonaDeclarada': {'nombre': 'Chapinero', 'nivel': 'LOCALIDAD'},
          'creadaEn': '2026-10-28T10:00:00Z',
          'actualizadaEn': '2026-10-28T11:00:00Z',
          'penalizacion': {
            'aplicada': true,
            'monto': 20000,
            'motivo': 'Cancelación tardía',
          },
        });
        expect(seg.penalizacionAplicada, isTrue);
        expect(seg.penalizacionMonto, 20000);
        expect(seg.penalizacionMotivo, 'Cancelación tardía');
      },
    );
  });
}
