import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/core/di/injection_container.dart';
import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/features/profiles/direct_employees/data/empleados_directos_remote_datasource.dart';
import 'package:mani/features/profiles/direct_employees/domain/usecases/registrar_empleado_directo_usecase.dart';
import 'package:mani/features/profiles/direct_employees/presentation/bloc/empleado_directo_cubit.dart';
import 'package:mani/features/profiles/direct_employees/presentation/pages/registrar_empleado_directo_page.dart';
import 'package:mani/features/services/categories/data/datasources/categorias_remote_datasource.dart';

/// Sin categorías dadas, la pantalla carga las activas del catálogo del tenant
/// de la sesión en lugar de los UUID fijos de la semilla de desarrollo.
class _FakeCategorias implements CategoriasRemoteDataSource {
  _FakeCategorias(this._respuestas);

  final List<Future<List<Map<String, dynamic>>> Function()> _respuestas;
  int llamadas = 0;

  @override
  Future<List<Map<String, dynamic>>> listar() => _respuestas[llamadas++]();

  @override
  Future<Map<String, dynamic>> crear({
    required String nombre,
    required String flujoOperativo,
    required bool activa,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> cambiarEstado({
    required String categoriaId,
    required bool activa,
  }) => throw UnimplementedError();

  @override
  String? get tenantIdSesion => null;
}

void main() {
  late EmpleadoDirectoCubit cubit;

  setUp(() {
    cubit = EmpleadoDirectoCubit(
      registrarUseCase: RegistrarEmpleadoDirectoUseCase(
        EmpleadosDirectosRepositoryImpl(
          remoteDataSource: EmpleadosDirectosRemoteDataSource(
            gateway: GatewayClient(
              baseUrl: 'http://gateway.local',
              tokenProvider: () async => null,
            ),
          ),
        ),
      ),
    );
  });

  tearDown(() async {
    await cubit.close();
    if (sl.isRegistered<CategoriasRemoteDataSource>()) {
      await sl.unregister<CategoriasRemoteDataSource>();
    }
  });

  Future<_FakeCategorias> montar(
    WidgetTester tester,
    List<Future<List<Map<String, dynamic>>> Function()> respuestas,
  ) async {
    final fake = _FakeCategorias(respuestas);
    sl.registerSingleton<CategoriasRemoteDataSource>(fake);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const RegistrarEmpleadoDirectoPage(),
        ),
      ),
    );
    return fake;
  }

  testWidgets('muestra solo las categorías activas del catálogo', (
    tester,
  ) async {
    await montar(tester, [
      () async => [
        {'id': 'c-1', 'name': 'Plomería', 'active': true},
        {'id': 'c-2', 'name': 'Oculta', 'active': false},
      ],
    ]);
    expect(
      find.byKey(const Key('categorias_empleado_cargando')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chk_categoria_c-1')), findsOneWidget);
    expect(find.byKey(const Key('chk_categoria_c-2')), findsNothing);
    expect(find.textContaining('d0eebc99'), findsNothing);
  });

  testWidgets('si falla la carga permite reintentar', (tester) async {
    final fake = await montar(tester, [
      () async => throw Exception('sin red'),
      () async => [
        {'id': 'c-1', 'name': 'Plomería', 'active': true},
      ],
    ]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('categorias_empleado_error')), findsOneWidget);

    final reintentar = find.text('Reintentar');
    await tester.ensureVisible(reintentar);
    await tester.tap(reintentar);
    await tester.pumpAndSettle();

    expect(fake.llamadas, 2);
    expect(find.byKey(const Key('chk_categoria_c-1')), findsOneWidget);
  });

  testWidgets('sin categorías activas muestra el aviso', (tester) async {
    await montar(tester, [() async => []]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('categorias_empleado_vacias')), findsOneWidget);
  });
}
