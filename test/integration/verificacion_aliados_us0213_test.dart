// Test maestro de US-02.1.3 — Aprobar/rechazar registro de aliado (QS-04).
//
// Recorre la historia de punta a punta con TODAS las capas reales:
//   BandejaVerificacionPage → BandejaVerificacionCubit → casos de uso →
//   VerificacionAliadosRepositoryImpl → VerificacionRemoteDataSource
// Solo se sustituye Supabase por `ServidorVerificacionFake`, que replica las
// reglas de las RPC de `002_verificacion_aliados.sql` (tenant desde la sesión,
// 404 entre tenants, 409 por decisión concurrente, 422 de validación).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/logging/structured_logger.dart';
import 'package:mani/features/profiles/verification/data/repositories/verificacion_aliados_repository_impl.dart';
import 'package:mani/features/profiles/verification/domain/entities/decision_verificacion.dart';
import 'package:mani/features/profiles/verification/presentation/pages/bandeja_verificacion_page.dart';

import '../features/profiles/verification/fakes.dart';

const _tenantA = 'tenant-a';
const _tenantB = 'tenant-b';

ServidorVerificacionFake _servidorConRegistros() {
  final s = ServidorVerificacionFake(tenantSesion: _tenantA)
    ..registrarAliado(
      id: 'carlos',
      tenantId: _tenantA,
      nombre: 'Carlos Mendoza',
      email: 'carlos@correo.com',
      categorias: ['Plomería'],
      fecha: DateTime.now().subtract(const Duration(days: 4)),
      documentos: [
        (
          id: 'c-ced',
          tipo: 'CEDULA_CIUDADANIA',
          ruta: 'kyc/tenant-a/cedula_carlos.pdf',
        ),
        (
          id: 'c-rut',
          tipo: 'RUT_CERTIFICADO',
          ruta: 'kyc/tenant-a/rut_carlos.pdf',
        ),
      ],
    )
    ..registrarAliado(
      id: 'tecnisur',
      tenantId: _tenantA,
      nombre: 'Tecnisur SAS',
      tipo: 'PERSONA_JURIDICA',
      email: 'contacto@tecnisur.com',
      categorias: ['Electricidad'],
      fecha: DateTime.now().subtract(const Duration(days: 1)),
      documentos: [
        (
          id: 't-cam',
          tipo: 'CAMARA_COMERCIO',
          ruta: 'kyc/tenant-a/camara_tecnisur.pdf',
        ),
        (
          id: 't-rut',
          tipo: 'RUT_EMPRESA',
          ruta: 'kyc/tenant-a/rut_tecnisur.pdf',
        ),
        (
          id: 't-rep',
          tipo: 'CEDULA_REPRESENTANTE',
          ruta: 'kyc/tenant-a/rep_tecnisur.png',
        ),
      ],
    )
    // Aliado de OTRA franquicia: nunca debe aparecer en la bandeja del tenant A.
    ..registrarAliado(
      id: 'intruso',
      tenantId: _tenantB,
      nombre: 'Aliado De Otro Tenant',
      documentos: [
        (id: 'x', tipo: 'CEDULA_CIUDADANIA', ruta: 'kyc/tenant-b/x.pdf'),
      ],
    );
  s.archivosSubidos.add('kyc/tenant-a/cedula_carlos.pdf');
  return s;
}

class _App {
  _App(this.servidor, this.logs, this.opener);
  final ServidorVerificacionFake servidor;
  final List<Map<String, dynamic>> logs;
  final FakeUrlOpener opener;
}

Future<_App> _montarApp(
  WidgetTester t,
  ServidorVerificacionFake servidor,
) async {
  t.view.physicalSize = const Size(1400, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);

  final logs = <Map<String, dynamic>>[];
  final opener = FakeUrlOpener();
  final repo = VerificacionAliadosRepositoryImpl(
    servidor,
    logger: StructuredLogger(
      canal: 'test',
      sink: (l) => logs.add(jsonDecode(l) as Map<String, dynamic>),
    ),
  );
  final cubit = crearCubit(repo, opener: opener);
  addTearDown(cubit.close);

  await t.pumpWidget(
    MaterialApp(
      home: BlocProvider.value(
        value: cubit,
        child: const BandejaVerificacionPage(),
      ),
    ),
  );
  await cubit.cargar();
  await t.pumpAndSettle();
  return _App(servidor, logs, opener);
}

Future<void> _abrir(WidgetTester t, String aliadoId) async {
  await t.tap(find.byKey(ValueKey('card-aliado-$aliadoId')));
  await t.pumpAndSettle();
}

Future<void> _aprobar(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('btn-aprobar')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('dlg-confirmar-aprobar')));
  await t.pumpAndSettle();
}

Future<void> _rechazar(WidgetTester t, String motivo) async {
  await t.tap(find.byKey(const ValueKey('btn-rechazar')));
  await t.pumpAndSettle();
  await t.enterText(find.byKey(const ValueKey('campo-motivo-rechazo')), motivo);
  await t.tap(find.byKey(const ValueKey('dlg-confirmar-rechazar')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'US-02.1.3 flujo completo: el admin revisa, aprueba a uno y rechaza a otro con motivo',
    (t) async {
      final app = await _montarApp(t, _servidorConRegistros());

      // CA-1 · QS-04: los registros pendientes del tenant aparecen en la bandeja,
      // en orden de llegada, y ningún aliado de otro tenant es visible.
      expect(find.bySemanticsLabel('Pendientes: 2'), findsOneWidget);
      expect(find.text('Carlos Mendoza'), findsOneWidget);
      expect(find.text('Tecnisur SAS'), findsOneWidget);
      expect(find.text('Aliado De Otro Tenant'), findsNothing);
      final yCarlos = t
          .getTopLeft(find.byKey(const ValueKey('card-aliado-carlos')))
          .dy;
      final yTecnisur = t
          .getTopLeft(find.byKey(const ValueKey('card-aliado-tecnisur')))
          .dy;
      expect(
        yCarlos,
        lessThan(yTecnisur),
        reason: 'FIFO: quien más espera va primero',
      );

      // CA-2: el detalle muestra el perfil con TODOS sus documentos.
      await _abrir(t, 'carlos');
      expect(find.text('Documentos KYC (2)'), findsOneWidget);
      expect(find.text('Cédula de ciudadanía'), findsOneWidget);
      expect(find.text('RUT / Certificación'), findsOneWidget);

      // CA-3: el admin puede abrir el documento (URL firmada, no pública).
      await t.tap(find.byKey(const ValueKey('ver-doc-c-ced')));
      await t.pumpAndSettle();
      expect(
        app.opener.abiertas.single.queryParameters,
        containsPair('token', 'abc'),
      );

      // CA-4: aprobar → el aliado queda VERIFICADO, sus documentos también, y
      // se le notifica sin que tenga que preguntar (QS-04).
      await _aprobar(t);
      expect(app.servidor.estadoDe('carlos'), 'VERIFICADO');
      expect(
        app.servidor.notificaciones.last,
        containsPair('decision', 'VERIFICADO'),
      );
      expect(
        find.textContaining('Carlos Mendoza fue aprobado'),
        findsOneWidget,
      );

      // La bandeja avanza sola al siguiente pendiente: Tecnisur (empresa, 3 documentos).
      expect(find.text('Documentos KYC (3)'), findsOneWidget);

      // CA-5: rechazar exige motivo; con motivo válido queda RECHAZADO y se
      // notifica al aliado con el motivo.
      const motivo =
          'La cámara de comercio tiene más de 90 días. Carga una vigente.';
      await _rechazar(t, motivo);
      expect(app.servidor.estadoDe('tecnisur'), 'RECHAZADO');
      expect(app.servidor.notificaciones.last, containsPair('motivo', motivo));

      // Bandeja al día y conteos coherentes.
      expect(find.text('¡Bandeja al día!'), findsOneWidget);
      expect(find.bySemanticsLabel('Pendientes: 0'), findsOneWidget);
      expect(find.bySemanticsLabel('Aprobados: 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Rechazados: 1'), findsOneWidget);

      // CA-6: el historial conserva la decisión y el motivo.
      await t.tap(find.byKey(const ValueKey('tab-rechazado')));
      await t.pumpAndSettle();
      await _abrir(t, 'tecnisur');
      expect(
        find.byKey(const ValueKey('resultado-verificacion')),
        findsOneWidget,
      );
      expect(find.text(motivo), findsOneWidget);

      // Trazabilidad: un log estructurado por decisión, sin datos personales.
      final decisiones = app.logs
          .where((l) => l['event'] == 'US-02.1.3.resolver_verificacion')
          .toList();
      expect(decisiones.map((l) => l['decision']), ['VERIFICADO', 'RECHAZADO']);
      expect(decisiones.every((l) => l['tenant_id'] == _tenantA), isTrue);
      expect(jsonEncode(app.logs), isNot(contains('carlos@correo.com')));
    },
  );

  testWidgets(
    'dos administradores deciden a la vez: solo cuenta la primera decisión',
    (t) async {
      final servidor = _servidorConRegistros();
      await _montarApp(t, servidor);

      // El admin A abre a Carlos (aún pendiente en su pantalla)…
      await _abrir(t, 'carlos');
      expect(find.byKey(const ValueKey('btn-aprobar')), findsOneWidget);

      // …mientras el admin B lo rechaza desde otro dispositivo.
      await VerificacionAliadosRepositoryImpl(
        servidor,
        logger: StructuredLogger(canal: 'b', sink: (_) {}),
      ).resolver(
        'carlos',
        DecisionVerificacion.rechazar('Documento ilegible, vuelve a cargarlo.'),
      );

      // El admin A intenta aprobar: el servidor responde 409.
      await _aprobar(t);

      expect(
        servidor.estadoDe('carlos'),
        'RECHAZADO',
        reason: 'la decisión de B no se sobrescribe',
      );
      expect(
        servidor.notificaciones,
        hasLength(1),
        reason: 'el aliado recibe una sola notificación',
      );
      expect(
        find.textContaining('Otro administrador ya resolvió'),
        findsOneWidget,
      );
      // La pantalla de A se actualiza con el estado real.
      expect(
        find.byKey(const ValueKey('resultado-verificacion')),
        findsOneWidget,
      );
      expect(
        find.text('Documento ilegible, vuelve a cargarlo.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('un usuario que no es ADMIN_TENANT no ve la bandeja', (t) async {
    final servidor = _servidorConRegistros()..rolSesion = 'ALIADO';
    await _montarApp(t, servidor);

    expect(
      find.text('Solo el administrador del tenant puede verificar aliados.'),
      findsOneWidget,
    );
    expect(find.text('Carlos Mendoza'), findsNothing);
  });

  testWidgets('sesión expirada: se pide volver a iniciar sesión', (t) async {
    final servidor = _servidorConRegistros()..haySesion = false;
    await _montarApp(t, servidor);

    expect(find.textContaining('Tu sesión expiró'), findsOneWidget);
  });

  testWidgets('un documento que no está en Storage muestra un mensaje claro', (
    t,
  ) async {
    final app = await _montarApp(t, _servidorConRegistros());

    await _abrir(t, 'tecnisur');
    await t.tap(find.byKey(const ValueKey('ver-doc-t-cam')));
    await t.pumpAndSettle();

    expect(app.opener.abiertas, isEmpty);
    expect(
      find.textContaining('No pudimos abrir el documento'),
      findsOneWidget,
    );
  });
}
