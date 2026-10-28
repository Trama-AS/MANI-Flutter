import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/catalog/data/zonas_catalogo_remote_datasource.dart';
import 'package:mani/features/catalog/domain/entities/zona_catalogo.dart';
import 'package:mani/features/catalog/presentation/sedes_con_zonas_del_catalogo.dart';

/// HU-M04-04: la pantalla de sedes no se abre con una lista de zonas fija.
/// Mientras el catálogo responde se espera, y si no hay catálogo se avisa en
/// lugar de ofrecer zonas inventadas que la base rechazaría al guardar.
class _ZonasFalsas implements IZonasCatalogoRemoteDataSource {
  _ZonasFalsas({this.falla = false, this.demora});

  final bool falla;
  final Duration? demora;

  @override
  Future<Map<String, String>> opcionesSeleccionables({String? nivel}) async {
    if (demora != null) await Future<void>.delayed(demora!);
    if (falla) throw Exception('el Gateway no respondió');
    // Catálogo vacío: la pantalla debe avisar, no ofrecer zonas inventadas.
    return const {};
  }

  @override
  Future<List<ZonaCatalogo>> consultarJerarquia({
    bool soloActivas = true,
  }) async => const [];
}

void main() {
  Widget pantallaCon(IZonasCatalogoRemoteDataSource ds) => MaterialApp(
    home: SedesConZonasDelCatalogo(clienteId: 'cli-1', zonasDataSource: ds),
  );

  testWidgets('muestra un indicador mientras el catálogo responde', (
    tester,
  ) async {
    // El catálogo demora y luego falla: así la prueba se queda en el estado
    // de carga sin llegar a montar la pantalla de sedes, que necesita su
    // Cubit y no es lo que se está comprobando acá.
    await tester.pumpWidget(
      pantallaCon(
        _ZonasFalsas(falla: true, demora: const Duration(seconds: 1)),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('cargando_zonas_catalogo')), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byKey(const Key('error_zonas_catalogo')), findsOneWidget);
  });

  testWidgets('si el catálogo falla avisa en vez de ofrecer zonas inventadas', (
    tester,
  ) async {
    await tester.pumpWidget(pantallaCon(_ZonasFalsas(falla: true)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error_zonas_catalogo')), findsOneWidget);
    expect(find.byKey(const Key('dropdown_zona_sede')), findsNothing);
  });

  testWidgets('si el catálogo llega vacío también avisa', (tester) async {
    await tester.pumpWidget(pantallaCon(_ZonasFalsas()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error_zonas_catalogo')), findsOneWidget);
  });
}
