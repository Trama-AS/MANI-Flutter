import 'package:flutter/material.dart';
import 'package:mani/features/catalog/data/zonas_catalogo_remote_datasource.dart';
import 'package:mani/features/profiles/company_sites/presentation/pages/gestion_sedes_empresa_page.dart';

/// Carga el catálogo geográfico antes de abrir la gestión de sedes
/// (HU-M04-04, C1: las zonas activas se pueden seleccionar en las interfaces
/// que consumen el catálogo).
///
/// Mientras responde el Gateway se muestra un indicador. Si el catálogo falla
/// o llega vacío se muestra el error en lugar de caer a una lista fija de
/// zonas: una zona inventada se rechaza al crear la sede, así que el respaldo
/// daría un formulario que parece funcionar y no funciona.
class SedesConZonasDelCatalogo extends StatelessWidget {
  const SedesConZonasDelCatalogo({
    super.key,
    required this.clienteId,
    required this.zonasDataSource,
  });

  final String clienteId;
  final IZonasCatalogoRemoteDataSource zonasDataSource;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: zonasDataSource.opcionesSeleccionables(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                key: Key('cargando_zonas_catalogo'),
              ),
            ),
          );
        }
        final zonas = snapshot.data;
        if (snapshot.hasError || zonas == null || zonas.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Sedes de la empresa')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No se pudo cargar el catálogo de zonas. '
                  'Sin zonas no es posible registrar una sede.',
                  key: Key('error_zonas_catalogo'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return GestionSedesEmpresaPage(
          clienteId: clienteId,
          zonasDisponibles: zonas,
        );
      },
    );
  }
}
