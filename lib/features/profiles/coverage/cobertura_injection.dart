import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/datasources/cobertura_remote_datasource.dart';
import 'data/repositories/cobertura_repository_impl.dart';
import 'presentation/controllers/cobertura_controller.dart';
import 'presentation/pages/declarar_cobertura_page.dart';

/// Composición de la feature. Si el proyecto ya tiene un contenedor de DI
/// (get_it / Riverpod), registrar ahí estas tres piezas y borrar este archivo.
CoberturaController crearCoberturaController([SupabaseClient? client]) =>
    CoberturaController(
      CoberturaRepositoryImpl(
        SupabaseCoberturaDataSource(client ?? Supabase.instance.client),
      ),
    );

/// Ruta de ejemplo: `Navigator.push(context, rutaDeclararCobertura())`.
/// Mostrar la entrada solo cuando `app_metadata.rol == 'aliado'`.
Route<void> rutaDeclararCobertura() => MaterialPageRoute(
  builder: (_) => _CoberturaHost(),
  settings: const RouteSettings(name: '/aliado/cobertura'),
);

class _CoberturaHost extends StatefulWidget {
  @override
  State<_CoberturaHost> createState() => _CoberturaHostState();
}

class _CoberturaHostState extends State<_CoberturaHost> {
  late final CoberturaController _controller = crearCoberturaController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      DeclararCoberturaPage(controller: _controller);
}
