import 'dart:async';

import 'package:mani/features/services/categories/data/datasources/categorias_remote_datasource.dart';
import 'package:mani/features/services/categories/domain/entities/categoria_servicio.dart';
import 'package:mani/features/services/categories/domain/entities/flujo_operativo.dart';
import 'package:mani/features/services/categories/domain/entities/nueva_categoria.dart';
import 'package:mani/features/services/categories/domain/failures/categoria_failure.dart';
import 'package:mani/features/services/categories/domain/repositories/categorias_repository.dart';
import 'package:mani/features/services/categories/domain/usecases/categoria_usecases.dart';
import 'package:mani/features/services/categories/presentation/bloc/categorias_cubit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------- builders
CategoriaServicio categoria(
  String nombre, {
  String? id,
  bool activa = true,
  FlujoOperativo? flujo = FlujoOperativo.cotizacionPrevia,
  int aliados = 0,
}) => CategoriaServicio(
  id: id ?? 'cat-${nombre.toLowerCase().replaceAll(' ', '-')}',
  nombre: nombre,
  activa: activa,
  flujo: flujo,
  aliadosAsociados: aliados,
);

// ------------------------------------------------ repositorio en memoria
/// Repositorio de dominio en memoria. Replica el índice único por nombre
/// (sin distinguir mayúsculas) de la migración 003.
class FakeCategoriasRepository implements CategoriasRepository {
  FakeCategoriasRepository([List<CategoriaServicio> iniciales = const []])
    : _datos = List.of(iniciales);

  final List<CategoriaServicio> _datos;

  CategoriaFailure? fallarAlListar;
  CategoriaFailure? fallarAlCrear;

  /// Si se asigna, `crear` espera a que se complete (para ver "guardando").
  Completer<void>? pausaCrear;

  int llamadasCrear = 0;
  NuevaCategoria? ultimaCreada;
  int _secuencia = 0;

  List<CategoriaServicio> get guardadas => List.unmodifiable(_datos);

  /// Simula que otro administrador creó la categoría en paralelo.
  void creadaPorOtroAdmin(String nombre) => _datos.add(categoria(nombre));

  @override
  Future<List<CategoriaServicio>> listar() async {
    if (fallarAlListar != null) {
      throw fallarAlListar!;
    }
    return List.of(_datos);
  }

  @override
  Future<CategoriaServicio> crear(NuevaCategoria nueva) async {
    llamadasCrear++;
    ultimaCreada = nueva;
    if (pausaCrear != null) {
      await pausaCrear!.future;
    }
    if (fallarAlCrear != null) {
      throw fallarAlCrear!;
    }
    if (nueva.duplicadaEn(_datos) != null) {
      throw const CategoriaFailure(CategoriaErrorTipo.nombreDuplicado);
    }
    final creada = CategoriaServicio(
      id: 'nueva-${++_secuencia}',
      nombre: nueva.nombre,
      activa: nueva.activa,
      flujo: nueva.flujo,
      fechaCreacion: DateTime.now(),
    );
    _datos.add(creada);
    return creada;
  }
}

CategoriasCubit crearCubit(CategoriasRepository repo) => CategoriasCubit(
  listar: ListarCategorias(repo),
  crear: CrearCategoria(repo),
);

// -------------------------------------------- servidor Supabase simulado
/// Simula, a nivel JSON, las RPC de `003_categorias_servicio.sql`: deriva
/// tenant y rol de la sesión, exige ADMIN_TENANT, valida nombre y flujo (422)
/// y aplica el índice único por tenant (409).
class ServidorCategoriasFake implements CategoriasRemoteDataSource {
  ServidorCategoriasFake({
    this.tenantSesion = 'tenant-a',
    this.rolSesion = 'ADMIN_TENANT',
    this.haySesion = true,
  });

  String tenantSesion;
  String rolSesion;
  bool haySesion;
  Object? errorDeRed;

  /// Filas "en BD" (incluye `tenant_id`, que nunca sale en la respuesta).
  final List<Map<String, dynamic>> filas = [];
  int _secuencia = 0;

  void sembrar({
    required String tenantId,
    required String nombre,
    String estado = 'ACTIVO',
    String flujo = 'COTIZACION_PREVIA',
    int aliados = 0,
  }) {
    filas.add({
      'tenant_id': tenantId,
      'id': 'semilla-${++_secuencia}',
      'nombre': nombre,
      'estado': estado,
      'flujo_operativo': flujo,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'aliados': aliados,
    });
  }

  List<Map<String, dynamic>> delTenant(String tenantId) =>
      filas.where((f) => f['tenant_id'] == tenantId).toList();

  void _exigirAdmin() {
    if (errorDeRed != null) {
      throw errorDeRed!;
    }
    if (!haySesion) {
      throw const PostgrestException(message: 'MANI-CAT-401: sesión requerida');
    }
    if (rolSesion != 'ADMIN_TENANT') {
      throw const PostgrestException(
        message: 'MANI-CAT-403: solo el administrador del tenant',
      );
    }
  }

  static Map<String, dynamic> _publica(Map<String, dynamic> f) =>
      Map<String, dynamic>.from(f)..remove('tenant_id');

  @override
  Future<List<Map<String, dynamic>>> listar() async {
    _exigirAdmin();
    final propias = delTenant(tenantSesion)
      ..sort(
        (a, b) => (a['nombre'] as String).toLowerCase().compareTo(
          (b['nombre'] as String).toLowerCase(),
        ),
      );
    return propias.map(_publica).toList();
  }

  @override
  Future<Map<String, dynamic>> crear({
    required String nombre,
    required String flujoOperativo,
    required bool activa,
  }) async {
    _exigirAdmin();
    final limpio = nombre.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (limpio.length < 3 ||
        limpio.length > 60 ||
        !RegExp(r'\p{L}', unicode: true).hasMatch(limpio)) {
      throw const PostgrestException(message: 'MANI-CAT-422N: nombre inválido');
    }
    final flujo = flujoOperativo.trim().toUpperCase();
    if (flujo != 'COTIZACION_PREVIA' && flujo != 'TARIFA_ESTANDAR') {
      throw PostgrestException(
        message: 'MANI-CAT-422F: flujo inválido ($flujo)',
      );
    }
    final clave = limpio.toLowerCase();
    final repetida = delTenant(
      tenantSesion,
    ).any((f) => (f['nombre'] as String).trim().toLowerCase() == clave);
    if (repetida) {
      throw PostgrestException(message: 'MANI-CAT-409: ya existe "$limpio"');
    }
    final fila = {
      'tenant_id': tenantSesion,
      'id': 'creada-${++_secuencia}',
      'nombre': limpio,
      'estado': activa ? 'ACTIVO' : 'INACTIVO',
      'flujo_operativo': flujo,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'aliados': 0,
    };
    filas.add(fila);
    return _publica(fila);
  }

  @override
  String? get tenantIdSesion => tenantSesion;
}
