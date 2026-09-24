import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:mani/core/platform/selector_fotos.dart';
import 'package:mani/features/services/requests/data/datasources/solicitudes_cliente_remote_datasource.dart';
import 'package:mani/features/services/requests/domain/entities/catalogo_solicitud.dart';
import 'package:mani/features/services/requests/domain/entities/nueva_solicitud.dart';
import 'package:mani/features/services/requests/domain/entities/solicitud_publicada.dart';
import 'package:mani/features/services/requests/domain/failures/solicitud_failure.dart';
import 'package:mani/features/services/requests/domain/repositories/solicitudes_cliente_repository.dart';
import 'package:mani/features/services/requests/domain/usecases/solicitud_usecases.dart';
import 'package:mani/features/services/requests/presentation/bloc/crear_solicitud_cubit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------- datos
/// PNG válido de 1×1 px (las miniaturas lo decodifican sin error).
final Uint8List pngMinimo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

ArchivoLocal foto(String nombre, {int? bytes}) => ArchivoLocal(
  nombre: nombre,
  bytes: bytes == null ? pngMinimo : Uint8List(bytes),
);

const plomeria = CategoriaDisponible(
  id: 'cat-plo',
  nombre: 'Plomería',
  modalidad: ModalidadCobro.cotizacionPrevia,
);
const cerrajeria = CategoriaDisponible(
  id: 'cat-cer',
  nombre: 'Cerrajería',
  modalidad: ModalidadCobro.tarifaEstandar,
);
const casa = SitioCliente(
  id: 'sitio-casa',
  direccion: 'Calle Colima 120, Apto 401',
  zona: 'Roma Norte',
  zonaPadre: 'Cuauhtémoc',
);
const romaNorte = ZonaOpcion(
  id: 'z-roma',
  nombre: 'Roma Norte',
  zonaPadre: 'Cuauhtémoc',
);
const polanco = ZonaOpcion(
  id: 'z-polanco',
  nombre: 'Polanco',
  zonaPadre: 'Miguel Hidalgo',
);

const descripcionValida =
    'La tubería debajo del lavaplatos gotea desde ayer y moja el piso.';

// ------------------------------------------------ repositorio en memoria
class FakeSolicitudesClienteRepository implements SolicitudesClienteRepository {
  FakeSolicitudesClienteRepository({
    this.categorias = const [plomeria, cerrajeria],
    this.sitios = const [casa],
    this.zonas = const [romaNorte, polanco],
  });

  List<CategoriaDisponible> categorias;
  List<SitioCliente> sitios;
  List<ZonaOpcion> zonas;

  SolicitudFailure? fallarAlCargar;
  SolicitudFailure? fallarAlPublicar;
  Completer<void>? pausaPublicar;

  int llamadasPublicar = 0;
  int llamadasBuscar = 0;
  final List<NuevaSolicitud> publicadas = [];

  @override
  Future<List<CategoriaDisponible>> categoriasDisponibles() async {
    if (fallarAlCargar != null) {
      throw fallarAlCargar!;
    }
    return categorias;
  }

  @override
  Future<List<SitioCliente>> misSitios() async {
    if (fallarAlCargar != null) {
      throw fallarAlCargar!;
    }
    return sitios;
  }

  @override
  Future<List<ZonaOpcion>> buscarZonas(String texto) async {
    llamadasBuscar++;
    final t = texto.toLowerCase();
    return zonas.where((z) => z.nombre.toLowerCase().contains(t)).toList();
  }

  @override
  Future<SolicitudPublicada> publicar(NuevaSolicitud solicitud) async {
    llamadasPublicar++;
    if (pausaPublicar != null) {
      await pausaPublicar!.future;
    }
    if (fallarAlPublicar != null) {
      throw fallarAlPublicar!;
    }
    publicadas.add(solicitud);
    final (direccion, zona, padre) = switch (solicitud.ubicacion) {
      SitioExistente(:final sitio) => (
        sitio.direccion,
        sitio.zona,
        sitio.zonaPadre,
      ),
      NuevaDireccion(:final direccion, :final zona) => (
        direccion,
        zona.nombre,
        zona.zonaPadre,
      ),
    };
    return SolicitudPublicada(
      id: 'sol-${publicadas.length}',
      categoria: solicitud.categoria.nombre,
      modalidad: solicitud.categoria.modalidad,
      descripcion: solicitud.descripcion,
      direccion: direccion,
      zona: zona,
      zonaPadre: padre,
      cantidadFotos: solicitud.fotos.length,
      fechaCreacion: DateTime.now(),
    );
  }
}

class FakeSelectorFotos implements SelectorFotos {
  FakeSelectorFotos([this.siguiente = const []]);

  /// Lo que "elegirá" el usuario la próxima vez.
  List<ArchivoLocal> siguiente;
  int aperturas = 0;

  @override
  Future<List<ArchivoLocal>> seleccionar() async {
    aperturas++;
    return siguiente;
  }
}

CrearSolicitudCubit crearCubit(
  SolicitudesClienteRepository repo, {
  String Function()? generarClave,
}) {
  var n = 0;
  return CrearSolicitudCubit(
    cargarCatalogo: CargarCatalogoSolicitud(repo),
    buscarZonas: BuscarZonas(repo),
    publicar: PublicarSolicitud(repo),
    generarClave:
        generarClave ?? () => '00000000-0000-4000-8000-00000000000${++n}',
  );
}

// -------------------------------------------- servidor Supabase simulado
/// Simula las RPC de `006_crear_solicitud.sql` y el bucket privado
/// `solicitudes` para un cliente autenticado.
class ServidorSolicitudesFake implements SolicitudesClienteRemoteDataSource {
  ServidorSolicitudesFake({
    this.usuario = 'uid-ana',
    this.tenant = 'tenant-a',
    this.esCliente = true,
  });

  String? usuario;
  String tenant;
  bool esCliente;

  /// Categorías de TODOS los tenants: {id, tenant_id, nombre, flujo, estado}.
  final List<Map<String, dynamic>> categorias = [];
  final List<Map<String, dynamic>> sitios = [];
  final List<Map<String, dynamic>> zonas = [];
  final List<Map<String, dynamic>> solicitudes = [];
  final List<Map<String, dynamic>> eventos = [];

  /// Objetos en Storage: ruta → bytes.
  final Map<String, Uint8List> storage = {};

  Object? errorDeRed;
  bool fallarSubida = false;

  /// Si se asigna, `crear` falla con este mensaje de RPC.
  String? fallarCrearCon;

  /// Simula que la RPC se ejecuta en el servidor pero la respuesta se pierde
  /// por la red (una sola vez): el cliente no sabe si se creó.
  bool perderRespuestaUnaVez = false;

  void sembrarBase() {
    categorias.addAll([
      {
        'id': 'cat-plo',
        'tenant_id': 'tenant-a',
        'nombre': 'Plomería',
        'flujo_operativo': 'COTIZACION_PREVIA',
        'estado': 'ACTIVO',
      },
      {
        'id': 'cat-oculta',
        'tenant_id': 'tenant-a',
        'nombre': 'Pintura',
        'flujo_operativo': 'TARIFA_ESTANDAR',
        'estado': 'INACTIVO',
      },
      {
        'id': 'cat-otro-tenant',
        'tenant_id': 'tenant-b',
        'nombre': 'Electricidad MTY',
        'flujo_operativo': 'COTIZACION_PREVIA',
        'estado': 'ACTIVO',
      },
    ]);
    zonas.addAll([
      {
        'id': 'z-roma',
        'nombre': 'Roma Norte',
        'padre': 'Cuauhtémoc',
        'estado': 'ACTIVO',
      },
      {
        'id': 'z-condesa',
        'nombre': 'Condesa',
        'padre': 'Cuauhtémoc',
        'estado': 'ACTIVO',
      },
      {
        'id': 'z-vieja',
        'nombre': 'Roma Vieja',
        'padre': 'Cuauhtémoc',
        'estado': 'INACTIVO',
      },
    ]);
  }

  // ------------------------------------------------------------ utilidades
  void _exigirCliente() {
    if (errorDeRed != null) {
      throw errorDeRed!;
    }
    if (usuario == null) {
      throw const PostgrestException(message: 'MANI-SOL-401: sesión requerida');
    }
    if (!esCliente) {
      throw const PostgrestException(message: 'MANI-SOL-403C: no es cliente');
    }
  }

  Map<String, dynamic>? _zona(String? id) {
    for (final z in zonas) {
      if (z['id'] == id) {
        return z;
      }
    }
    return null;
  }

  Map<String, dynamic> _jsonSolicitud(Map<String, dynamic> s) {
    final sitio = sitios.firstWhere((x) => x['id'] == s['sitio_id']);
    final zona = _zona(sitio['zona_id'] as String)!;
    final cat = categorias.firstWhere((c) => c['id'] == s['categoria_id']);
    return {
      'id': s['id'],
      'estado': s['estado'],
      'categoria': cat['nombre'],
      'flujo_operativo': cat['flujo_operativo'],
      'descripcion': s['descripcion'],
      'direccion': sitio['direccion'],
      'zona': zona['nombre'],
      'zona_padre': zona['padre'],
      'fotos': (s['fotos'] as List).length,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  // ------------------------------------------------------------ datasource
  @override
  Future<List<Map<String, dynamic>>> listarCategorias() async {
    _exigirCliente();
    return categorias
        .where((c) => c['tenant_id'] == tenant && c['estado'] == 'ACTIVO')
        .map(
          (c) => {
            'id': c['id'],
            'nombre': c['nombre'],
            'flujo_operativo': c['flujo_operativo'],
          },
        )
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> listarSitios() async {
    _exigirCliente();
    return sitios.where((s) => s['cliente'] == usuario).map((s) {
      final z = _zona(s['zona_id'] as String)!;
      return {
        'id': s['id'],
        'direccion': s['direccion'],
        'zona': z['nombre'],
        'zona_padre': z['padre'],
      };
    }).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> buscarZonas(String texto) async {
    _exigirCliente();
    final t = texto.trim().toLowerCase();
    if (t.length < 2) {
      return const [];
    }
    return zonas
        .where((z) => z['estado'] == 'ACTIVO')
        .where((z) => (z['nombre'] as String).toLowerCase().contains(t))
        .map(
          (z) => {
            'id': z['id'],
            'nombre': z['nombre'],
            'zona_padre': z['padre'],
          },
        )
        .toList();
  }

  @override
  Future<void> subirFoto(String ruta, Uint8List bytes, String mime) async {
    if (errorDeRed != null) {
      throw errorDeRed!;
    }
    if (fallarSubida) {
      throw const StorageException('Upload failed', statusCode: '500');
    }
    // Política de Storage: solo en la carpeta propia.
    if (!ruta.startsWith('$usuario/')) {
      throw const StorageException('new row violates RLS', statusCode: '403');
    }
    storage[ruta] = bytes;
  }

  @override
  Future<void> eliminarFotos(List<String> rutas) async {
    for (final r in rutas) {
      storage.remove(r);
    }
  }

  @override
  Future<Map<String, dynamic>> crear({
    required String categoriaId,
    required String descripcion,
    required List<String> fotos,
    required String claveIdempotencia,
    String? sitioId,
    String? direccion,
    String? zonaId,
  }) async {
    _exigirCliente();
    if (fallarCrearCon != null) {
      throw PostgrestException(message: fallarCrearCon!);
    }
    for (final s in solicitudes) {
      if (s['cliente'] == usuario && s['clave'] == claveIdempotencia) {
        return _jsonSolicitud(s);
      }
    }
    final cat = categorias.where(
      (c) =>
          c['id'] == categoriaId &&
          c['tenant_id'] == tenant &&
          c['estado'] == 'ACTIVO',
    );
    if (cat.isEmpty) {
      throw const PostgrestException(message: 'MANI-SOL-422C: categoría');
    }
    final d = descripcion.trim();
    if (d.length < 20 || d.length > 1000) {
      throw const PostgrestException(message: 'MANI-SOL-422D: descripción');
    }
    if (fotos.length > 5 || fotos.any((f) => !f.startsWith('$usuario/'))) {
      throw const PostgrestException(message: 'MANI-SOL-422F: fotos');
    }
    String idSitio;
    if (sitioId != null) {
      final s = sitios.where(
        (x) => x['id'] == sitioId && x['cliente'] == usuario,
      );
      if (s.isEmpty) {
        throw const PostgrestException(message: 'MANI-SOL-422S: sitio');
      }
      idSitio = sitioId;
    } else {
      final dir = (direccion ?? '').trim();
      if (dir.length < 5 || dir.length > 200) {
        throw const PostgrestException(message: 'MANI-SOL-422S: dirección');
      }
      final z = _zona(zonaId);
      if (z == null || z['estado'] != 'ACTIVO') {
        throw const PostgrestException(message: 'MANI-SOL-422Z: zona');
      }
      idSitio = 'sitio-${sitios.length + 1}';
      sitios.add({
        'id': idSitio,
        'cliente': usuario,
        'tenant_id': tenant,
        'zona_id': zonaId,
        'direccion': dir,
      });
    }
    final fila = {
      'id': 'sol-${solicitudes.length + 1}',
      'tenant_id': tenant,
      'cliente': usuario,
      'categoria_id': categoriaId,
      'sitio_id': idSitio,
      'estado': 'PENDIENTE',
      'descripcion': d,
      'fotos': List<String>.of(fotos),
      'clave': claveIdempotencia,
    };
    solicitudes.add(fila);
    eventos.add({
      'solicitud_id': fila['id'],
      'tipo_evento': 'SOLICITUD_CREADA',
    });
    if (perderRespuestaUnaVez) {
      perderRespuestaUnaVez = false;
      throw TimeoutException('respuesta perdida');
    }
    return _jsonSolicitud(fila);
  }

  @override
  String? get usuarioId => usuario;

  @override
  String? get tenantIdSesion => tenant;
}
